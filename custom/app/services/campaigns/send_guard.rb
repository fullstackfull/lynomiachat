# frozen_string_literal: true

# THE LAST THING ASKED BEFORE A CAMPAIGN MESSAGE GOES TO A PROVIDER.
#
# `Campaigns::Eligibility` resolves who a campaign may address when its audience is resolved.
# This re-asks, per recipient, immediately before the provider call. That is not a backup
# guard for the same question -- it is a different question, because TIME HAS PASSED. A
# campaign is selected by a scheduler every five minutes and then iterates its whole audience
# in one job; between the audience being resolved and a given recipient being reached, the
# shopper can reply STOP, an agent can block them, the provider can report the number dead,
# an operator can revoke the integration, or the kill switch can be thrown. A snapshot records
# who was addressed; it was never evidence that they still may be.
#
# PRECEDENCE, EXACTLY AS APPROVED IN ADR-001 §3.3. First refusal wins; nothing below can
# overturn something above.
#
#   1  outbound kill switch            installation-wide
#   2  installation revoked            partner-originated sends only
#   3  contact blocked                 native, always
#   4  native suppression              native, always, per purpose
#   5  native withdrawal               native, always, per purpose
#   6  partner suppression in scope    partner-originated only
#   7  partner withdrawal in scope     partner-originated only
#   8  promotional with no grant       satisfied by EITHER store, each within its own scope
#   9  provider rules                  left to the sender that owns them
#
# NEGATIVES UNION AND POSITIVES DO NOT. Steps 3-7 mean either consent store can refuse and
# neither can overturn the other. Step 8 is the only place a positive is read, and a partner
# grant counts there only when the installation, the purpose and the channel all match.
#
# EACH NEGATIVE REACHES AS FAR AS ITS OWN SCOPE AND NO FURTHER. A native decision is
# account-wide, so it stops everything of that class. A partner decision is installation,
# purpose and channel scoped, so it stops that store's messages of that class on that channel
# and says nothing about another store or another class.
#
# STEP 9 IS DELIBERATELY NOT HERE. Template approval, the 24-hour window and the
# authentication-template guard belong to the sender that knows the channel, and each already
# refuses on its own terms. Restating them here would be a second copy to keep in step.
module Campaigns::SendGuard
  module_function

  # @return [Symbol, nil] nil when the send may proceed, else the refusal code
  def refusal(contact, campaign, channel)
    return :outbound_halted if Campaigns::Outbound.halted?(campaign.account)

    purpose = Campaigns::Eligibility.purpose_for(campaign)
    native = Commerce::MessagingEligibility.refusal(contact, purpose)
    store = campaign.commerce_store

    return native_or_partner(native, contact, store, purpose, channel) if store

    native
  end

  def allows?(contact, campaign, channel) = refusal(contact, campaign, channel).nil?

  # A partner-originated send answers to both stores. The native refusal is returned first
  # when it is one of the absolute ones (steps 3-5); a merely-missing native grant does not
  # refuse on its own, because a partner grant in scope is a legitimate basis for it.
  def native_or_partner(native, contact, store, purpose, channel)
    return native if native && native != :promotional_consent_missing

    partner = Partners::Eligibility.refusal(contact, store, purpose, channel)
    # Both stores lack a positive grant: report the native code, which is the one a merchant
    # recognises, rather than leaking which of two subsystems was asked last.
    return :promotional_consent_missing if native && partner == :partner_consent_missing

    partner
  end
end
