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
# A CAMPAIGN IS PROMOTIONAL. Not a decision taken here -- `Commerce::MessagingConsent`'s own
# documentation says so: "promotional: an abandoned basket, A CAMPAIGN, anything the shopper
# did not ask for. It is refused unless they said yes."
#
# BUT THE GRANT REQUIREMENT IS CONDITIONAL AND THE REFUSALS ARE NOT, and that asymmetry is
# deliberate:
#
#   REFUSALS ALWAYS APPLY. Blocked, withdrawn and suppressed are explicit facts about a person
#   -- somebody said stop, or the provider said it cannot be delivered. Honouring those must
#   never depend on a feature flag, so this half runs for every account on every campaign.
#
#   THE GRANT IS REQUIRED ONLY WHERE GRANTS CAN EXIST. `commerce_messaging_consents` is written
#   by the Commerce consent surface and the opt-out keyword listener. An account that does not
#   run Commerce has no rows and no way to collect any, so demanding a grant there would not be
#   enforcement -- it would silently reduce every campaign to zero recipients against data that
#   structurally cannot exist, with nothing on screen to explain it. Where the account DOES run
#   Commerce, the model's rule applies in full: no grant, no send.
module Campaigns::Eligibility
  BLOCKING_STATES = %i[withdrawn suppressed].freeze

  # The purpose a campaign's messages belong to. A constant rather than a literal so the one
  # place that would ever change it is visible.
  PURPOSE = :promotional

  module_function

  # @param relation [ActiveRecord::Relation] contacts the audience selected
  # @param account [Account]
  # @return [ActiveRecord::Relation] the subset this campaign may actually message
  def filter(relation, account)
    scope = relation.where(blocked: false).where.not(id: blocked_by_decision(account))
    return scope unless grant_required?(account)

    scope.where(id: granted(account))
  end

  # Why the audience shrank, as counts by the same reason codes Commerce::MessagingEligibility
  # returns. Served beside a preview count so "400 of 1,000" is answerable on screen rather
  # than being a number a merchant has to take on faith.
  #
  # Counted off the ORIGINAL relation, so the four numbers and the filtered count describe the
  # same population.
  def excluded_counts(relation, account)
    unavailable = relation.where(blocked: true)
    refused = relation.where(blocked: false).where(id: blocked_by_decision(account))

    counts = { contact_unavailable: unavailable.count,
               consent_withdrawn: refused.where(id: in_state(account, :withdrawn)).count,
               messaging_suppressed: refused.where(id: in_state(account, :suppressed)).count }
    counts[:promotional_consent_missing] = ungranted_count(relation, account) if grant_required?(account)
    counts
  end

  # Only where the consent model is actually operated; see the note at the top of this file.
  def grant_required?(account) = account.feature_enabled?('lynomia_commerce')

  def blocked_by_decision(account)
    Commerce::MessagingConsent.where(account_id: account.id, state: BLOCKING_STATES).select(:contact_id)
  end

  def in_state(account, state)
    Commerce::MessagingConsent.where(account_id: account.id, state: state).select(:contact_id)
  end

  def granted(account)
    Commerce::MessagingConsent.where(account_id: account.id, purpose: PURPOSE, state: :granted).select(:contact_id)
  end

  # Reachable but for the missing grant: not blocked, not refused, and not granted. Counted
  # this way rather than as a subtraction so it stays correct if a contact is both.
  def ungranted_count(relation, account)
    relation.where(blocked: false)
            .where.not(id: blocked_by_decision(account))
            .where.not(id: granted(account))
            .count
  end
end
