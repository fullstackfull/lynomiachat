# frozen_string_literal: true

# WHETHER A PARTNER-ORIGINATED MESSAGE MAY REACH THIS PERSON, for one installation, one
# purpose and one channel (docs/partner-consent/ADR-001-partner-scoped-consent.md).
#
# THIS ANSWERS ONLY THE PARTNER HALF. Lynomia's own refusals -- a blocked contact, a native
# withdrawal, a native suppression -- are Commerce::MessagingEligibility's answer and are
# checked separately. Neither half can overturn the other, which is the whole point of keeping
# them apart: a partner grant cannot talk past a native opt-out, and a native grant cannot
# talk past a partner withdrawal.
#
# NEGATIVES UNION, POSITIVES DO NOT. Both stores can refuse. Only a grant whose scope matches
# the send can permit, and "matches" means the same installation, the same purpose and a
# channel the customer was actually shown.
#
# A NEGATIVE REACHES EXACTLY AS FAR AS ITS OWN SCOPE, AND NO FURTHER. A shopper who turned off
# marketing from one store said something about that store's marketing. Treating it as
# "nothing from anyone, ever" would silence the parcel notifications they still want and a
# second merchant they never mentioned. Account-wide and installation-wide restrictions exist
# and are honoured -- they live in the native store and in the installation's own lifecycle --
# but they are different facts, recorded in different places, and this one is not widened to
# impersonate them.
#
# AN INSTALLATION THAT IS NOT `active` AUTHORISES NOTHING, and this is deliberately STRICTER
# than the `connected` scope used elsewhere in Commerce. `Commerce::Store.connected` means
# "not disconnected", so it still includes `disabled` and `needs_reauth` -- the right reading
# when counting a plan's stores or keeping a store's history, and the wrong one here. "May
# this integration vouch for a new outbound message right now" has to exclude one an operator
# has paused and one whose credentials have broken. The evidence survives in every state;
# only the authority to act on it is withdrawn.
#
# Read live rather than from any snapshot, so an integration revoked after a campaign was
# scheduled stops that campaign's remaining sends.
module Partners::Eligibility
  module_function

  # @param contact [Contact]
  # @param store [Commerce::Store] the partner installation the send belongs to
  # @param purpose [Symbol] :transactional or :promotional
  # @param channel [Symbol] :whatsapp, :sms or :email
  # @return [Symbol, nil] nil when the partner half permits the send, else a refusal code
  def refusal(contact, store, purpose, channel)
    return :installation_revoked unless store&.active?
    return :partner_scope_mismatch unless subject_of?(contact, store)

    scoped = in_scope(contact, store, purpose, channel)
    blocking_refusal(scoped) || grant_refusal(scoped, purpose)
  end

  def subject_of?(contact, store) = contact.present? && contact.account_id == store.account_id

  def blocking_refusal(scoped)
    blocking = scoped.blocking.first
    return nil if blocking.nil?

    blocking.consent_suppressed? ? :partner_suppressed : :partner_consent_withdrawn
  end

  # Transactional needs no grant here for the same reason it needs none natively: the customer
  # is party to the thing being messaged about, so only the absence of a refusal is required.
  def grant_refusal(scoped, purpose)
    return nil unless purpose.to_sym == :promotional

    :partner_consent_missing unless scoped.granted.exists?
  end

  def allows?(contact, store, purpose, channel) = refusal(contact, store, purpose, channel).nil?

  # The rows that speak to this exact send. Scope is the installation, the class and a channel
  # the capture covered -- a grant taken without naming a channel covers all of them, one
  # taken for a channel covers only that channel.
  def in_scope(contact, store, purpose, channel)
    PartnerConsent.where(commerce_store_id: store.id, contact_id: contact.id, purpose: purpose)
                  .for_channel(channel)
  end

  # The contacts of `relation` this installation may message, as a relation, for resolving an
  # audience. The per-contact decision above stays the authority at the send boundary;
  # spec/services/partners/eligibility_spec.rb asserts the two agree contact for contact.
  #
  # `native_granted` IS THE OTHER HALF OF ADR-001 §3.3 STEP 8 -- the contact ids the NATIVE
  # consent store has granted this purpose -- because the step is "no grant from EITHER
  # source" and a grant from either one satisfies it. Omitted, this required a grant from
  # THIS installation and nothing else, which excluded from the audience every shopper who
  # had agreed natively instead; Campaigns::SendGuard#native_or_partner made the same mistake
  # per recipient, so the two agreed with each other while both disagreed with the ADR.
  #
  # Passed in rather than read here, because the native store's grants are
  # Campaigns::Eligibility's to express and this module deliberately knows only the partner
  # half (see the note at the top). The default is "none", which is the honest answer for a
  # caller asking the partner half on its own -- spec/services/partners/eligibility_spec.rb's
  # agreement check is exactly such a caller.
  def filter(relation, store, purpose, channel, native_granted: nil)
    return relation.none unless store&.active?

    scope = relation.where.not(id: blocking_ids(store, purpose, channel))
    return scope unless purpose.to_sym == :promotional

    scope.where(id: granted_ids(store, purpose, channel)).or(scope.where(id: native_granted))
  end

  def blocking_ids(store, purpose, channel)
    PartnerConsent.where(commerce_store_id: store.id, purpose: purpose).for_channel(channel).blocking.select(:contact_id)
  end

  def granted_ids(store, purpose, channel)
    PartnerConsent.where(commerce_store_id: store.id, purpose: purpose).for_channel(channel).granted.select(:contact_id)
  end
end
