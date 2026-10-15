# frozen_string_literal: true

# WHO A CAMPAIGN MAY ACTUALLY REACH.
#
# Until this existed, no campaign sender checked anything. `Campaign#audience_contacts` was
# `account.contacts.tagged_with(...)` and nothing else, and all four senders, the pre-send
# preview and the recipient snapshot resolved their recipients through it. A contact who had
# replied STOP, a contact an agent had blocked, and a contact the provider had told us cannot
# receive were all addressed exactly like anyone else. `suppressed` is the worst of the three:
# it is set when the provider says the number is unreachable, so re-sending to it is what
# damages a sender's quality rating and eventually its messaging tier.
#
# WHY HERE AND NOWHERE ELSE. `audience_contacts` is the single shared entry point -- every
# sender, the `audience_preview` count and `Campaigns::RecipientSnapshot#seed` all call it --
# so one filter here covers every path and the preview necessarily agrees with the send. A
# check added to the four senders instead would be four copies, and the first one somebody
# forgot to update would be the one that messaged a person who had opted out.
#
# A RELATION, NOT A LOOP. The callers do `.each`, `.count` and `.seed` on what comes back, and
# a marketing audience is not a page -- deciding per contact in Ruby would be one query each
# and would make the preview count unusable. So the rule is expressed in SQL here while
# `Commerce::MessagingEligibility` keeps the per-contact decision, and
# spec/services/campaigns/eligibility_spec.rb asserts the two agree contact for contact over a
# fixture set covering every state. Two expressions of one rule are a drift hazard; an
# executable cross-check is what makes them one rule with two readings.
#
# WHAT CLASS A CAMPAIGN'S MESSAGES BELONG TO IS THE PROVIDER'S ANSWER, NOT THE ACCOUNT'S.
#
# An earlier version of this file required a promotional grant only where the account ran
# Commerce, reasoning that an account with no consent rows had no way to collect any. That was
# wrong in the one way that matters: it read the ABSENCE of a consent record as permission to
# market. Absence of a record is not consent, and an account that happens not to use Commerce
# is not thereby allowed to send promotional messages to people who never agreed.
#
# So the class is taken from the message itself, using the classification the provider already
# applies and enforces:
#
#   WhatsApp UTILITY      transactional. Meta approves a UTILITY template for messages about
#                         something the customer is already party to, and that is exactly the
#                         transactional class: allowed unless refused. A merchant sending order
#                         updates through an approved UTILITY template keeps working, on the
#                         provider's authority rather than on an assumption made here.
#   WhatsApp MARKETING    promotional. Meta requires opt-in for marketing templates, so this is
#                         the provider's own rule being honoured rather than a policy invented
#                         here: no grant, no send.
#   WhatsApp AUTHENTICATION  treated as promotional, which is conservative and harmless -- the
#                         authentication-template guard in the sender refuses these anyway.
#   SMS and Twilio SMS    no provider classification exists for a plain SMS blast, so it is
#                         promotional. The conservative default is the only safe one when
#                         nothing authoritative says otherwise.
#
# WHERE A NON-COMMERCE ACCOUNT STANDS, stated plainly because it is a real limitation and not a
# loophole. The consent STORE is universal: Commerce::ConsentListener writes a withdrawal for
# any account on any inbound STOP, so opt-outs are honoured everywhere. The grant SURFACE is
# not: Api::V1::Accounts::Commerce::ConsentsController is behind `ensure_commerce_enabled`, so
# an account without Commerce has no authorized way to record that a shopper agreed. The
# consequence is deliberate and is reported rather than hidden -- a promotional campaign from
# such an account reaches nobody, `excluded_counts` says `promotional_consent_missing` and how
# many, and the remedy is a UTILITY template for transactional sends or Commerce for marketing.
# Inventing a permission to fill that gap is the one thing this must not do.
#
module Campaigns::Eligibility
  BLOCKING_STATES = %i[withdrawn suppressed].freeze

  # Provider categories whose messages are transactional. Only Meta's UTILITY qualifies: it is
  # the one category the provider approves for messages about something the customer is already
  # part of. Everything else, and anything with no category at all, is promotional.
  TRANSACTIONAL_CATEGORIES = %w[UTILITY].freeze

  module_function

  # @return [Symbol] :transactional or :promotional, from the provider's own classification.
  def purpose_for(campaign)
    category = campaign.template_params.is_a?(Hash) ? campaign.template_params['category'].to_s.upcase : ''

    TRANSACTIONAL_CATEGORIES.include?(category) ? :transactional : :promotional
  end

  # @param relation [ActiveRecord::Relation] contacts the audience selected
  # @return [ActiveRecord::Relation] the subset this campaign may actually message
  # A REFUSAL BLOCKS THE CLASS IT WAS MADE AGAINST, NOT BOTH. Withdrawing marketing consent
  # must not silence a parcel notification -- that asymmetry is the whole point of the
  # two-class model, and Commerce::MessagingEligibility looks the decision up per purpose for
  # exactly that reason. A real opt-out is not weakened by this: Commerce::ConsentListener
  # writes BOTH classes from one STOP, "because that is what the person meant", so a keyword
  # refusal still stops everything. An earlier draft blocked on a refusal of any purpose and
  # the agreement spec below caught the divergence.
  def filter(relation, account, purpose)
    scope = relation.where(blocked: false).where.not(id: blocked_by_decision(account, purpose))
    return scope unless purpose.to_sym == :promotional

    scope.where(id: granted(account))
  end

  # Why the audience shrank, as counts by the same reason codes Commerce::MessagingEligibility
  # returns. Served beside a preview count so "400 of 1,000" is answerable on screen rather
  # than being a number a merchant has to take on faith.
  #
  # Counted off the ORIGINAL relation, so the four numbers and the filtered count describe the
  # same population.
  def excluded_counts(relation, account, purpose)
    refused = relation.where(blocked: false).where(id: blocked_by_decision(account, purpose))

    counts = { contact_unavailable: relation.where(blocked: true).count,
               consent_withdrawn: refused.where(id: in_state(account, purpose, :withdrawn)).count,
               messaging_suppressed: refused.where(id: in_state(account, purpose, :suppressed)).count }
    counts[:promotional_consent_missing] = ungranted_count(relation, account, purpose) if purpose.to_sym == :promotional
    counts
  end

  def blocked_by_decision(account, purpose)
    Commerce::MessagingConsent.where(account_id: account.id, purpose: purpose, state: BLOCKING_STATES).select(:contact_id)
  end

  def in_state(account, purpose, state)
    Commerce::MessagingConsent.where(account_id: account.id, purpose: purpose, state: state).select(:contact_id)
  end

  def granted(account)
    Commerce::MessagingConsent.where(account_id: account.id, purpose: :promotional, state: :granted).select(:contact_id)
  end

  # Reachable but for the missing grant: not blocked, not refused, and not granted. Counted
  # this way rather than as a subtraction so it stays correct if a contact is both.
  def ungranted_count(relation, account, purpose)
    relation.where(blocked: false)
            .where.not(id: blocked_by_decision(account, purpose))
            .where.not(id: granted(account))
            .count
  end
end
