# frozen_string_literal: true

# TELLING A PARTNER THAT A CUSTOMER'S CONSENT CHANGED HERE
# (docs/partner-consent/AUTHORITY.md §1: Lynomia is an origin too).
#
# The case this exists for is a shopper replying STOP on WhatsApp. That is a decision made on
# Lynomia's own channel, about a person the merchant knows as their customer, and the merchant
# finds out only if somebody tells them. Without this feed Store Syria's consent screen would
# show a cheerful "subscribed" for somebody who opted out days ago.
#
# NO NEW DELIVERY MECHANISM. Store Syria already registers an account Webhook pointing at its
# own signed ingress (EventSubscriptionManager#ensureSubscribed), and that ingress already
# verifies the signature, rate-limits per store and refuses a duplicate `delivery_id`. So a
# consent change is one more event type on a pipe that exists, with its retries, its signing
# and its de-duplication already built and already exercised.
#
# THE DELIVERY ID IS DERIVED, NOT RANDOM: from the decision's own identity and revision, so a
# reconciliation sweep or a republish after a deploy is a no-op at the receiver rather than a
# second decision. Partner::EventFan carries the fan-out and records why.
#
# ONE DELIVERY PER INSTALLATION, ADDRESSED IN THE PARTNER'S OWN TERMS. A partner cannot act on
# a Lynomia contact id, so the payload names the store and the customer id THAT STORE already
# uses, resolved through commerce_customer_links. A contact linked to two stores produces two
# deliveries, each scoped to one -- a store is never told about a customer that is not theirs.
module Consents::ChangeFeed
  EVENT = 'consent_changed'

  module_function

  # A decision recorded in Lynomia's NATIVE store -- an opt-out keyword, an agent's record, an
  # operator's suppression. Published to every installation that knows this person.
  def publish_native(consent)
    contact = consent.contact
    return if contact.nil?

    links(contact).each do |link|
      Partner::EventFan.publish(
        contact.account, EVENT, payload(link, consent, origin: 'lynomia_native', channel: 'any'),
        delivery_id: "consent-native-#{consent.id}-#{consent.updated_at.to_i}-#{link.commerce_store_id}"
      )
    end
  end

  # A decision this side applied on a PARTNER's behalf. Echoed back so a partner that lost its
  # own write, or that has several installations, converges on what Lynomia actually holds --
  # and so a re-consent refused here does not sit in the partner's UI looking accepted.
  def publish_partner(consent)
    Partner::EventFan.publish(consent.account, EVENT, partner_payload(consent),
                              delivery_id: "consent-partner-#{consent.id}-#{consent.revision}")
  end

  # Only the installations whose own customer this is. `connected` rather than `active`: a
  # paused integration may not AUTHORISE a send, but it must still be told that somebody
  # opted out, because that is the fact it will need when it resumes.
  #
  # `linked`, because a suppressed link is an agent saying this is NOT that store's
  # customer. Publishing to it anyway sent one shopper's opt-out to a merchant who had been
  # told the match was wrong -- a small leak, and of exactly the data this subsystem exists
  # to handle carefully.
  def links(contact)
    Commerce::CustomerLink.linked.joins(:store)
                          .where(contact_id: contact.id)
                          .where.not(commerce_stores: { status: Commerce::Store.statuses[:disconnected] })
  end

  # `account` travels because the receiver checks it. Store Syria's ingress refuses a
  # correctly signed delivery whose account is not the one that store is linked to -- a
  # signature proves who sent it, this proves what it may talk about -- so a payload without
  # it would be rejected as `unknown_workspace` however well formed it was.
  def payload(link, consent, origin:, channel:)
    { event: EVENT, origin: origin, account: { id: link.account_id },
      store: { provider: link.store.provider, external_store_id: link.store.external_store_id },
      subject: { external_customer_id: link.external_customer_id },
      purpose: consent.purpose, channel: channel, state: consent.state, source: consent.source,
      # `revision`, NOT `id`. The native row is updated in place, so its id is the same for
      # every decision in a scope and a receiver that drops anything at or below the highest
      # revision it holds would discard every decision after the first.
      # Commerce::MessagingConsents.write bumps this column on each write; the partner side's
      # own revision is already monotonic because it is one row per event.
      occurred_at: timestamp_of(consent), revision: consent.revision }
  end

  def partner_payload(consent)
    { event: EVENT, origin: 'partner', account: { id: consent.account_id },
      store: { provider: consent.commerce_store.provider,
               external_store_id: consent.commerce_store.external_store_id },
      subject: { external_customer_id: consent.external_subject_id },
      purpose: consent.purpose, channel: consent.channel, state: consent.state, source: consent.source,
      occurred_at: timestamp_of(consent), revision: consent.revision }
  end

  def timestamp_of(consent)
    stamp = consent.respond_to?(:captured_at) ? consent.captured_at : consent.decided_at
    (stamp || consent.updated_at).iso8601
  end
end
