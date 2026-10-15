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
#   2  campaign cancelled              this campaign only
#   3  installation revoked            partner-originated sends only
#   4  contact blocked                 native, always
#   5  native suppression              native, always, per purpose
#   6  native withdrawal               native, always, per purpose
#   7  partner suppression in scope    partner-originated only
#   8  partner withdrawal in scope     partner-originated only
#   9  promotional with no grant       satisfied by EITHER store, each within its own scope
#  10  provider rules                  left to the sender that owns them
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
# STEP 10 IS DELIBERATELY NOT HERE. Template approval, the 24-hour window and the
# authentication-template guard belong to the sender that knows the channel, and each already
# refuses on its own terms. Restating them here would be a second copy to keep in step.
module Campaigns::SendGuard
  module_function

  # THE WHOLE GATE, IN THE ONE ORDER THAT IS CORRECT: ask, pace, ask again.
  #
  # The senders used to call `refusal` and then `Campaigns::Throttle.pace`, in that order,
  # which quietly undid the point of asking late. Pacing sleeps -- up to MAX_WAIT per
  # recipient, and a large audience spends most of its wall-clock time inside those sleeps --
  # so a withdrawal, a kill switch or a revocation landing during the wait was read, found
  # nothing to stop, and the message went out anyway. The answer was taken before the wait and
  # acted on after it.
  #
  # WHY ASK TWICE RATHER THAN ONLY AFTER. The first ask is not a duplicate: it keeps a
  # recipient who is already refused from claiming a slot in the ceiling. A campaign whose
  # audience is mostly suppressed would otherwise pace itself against its own skips, turning a
  # ten-thousand-row audience with a thousand eligible recipients into a sixteen-minute run of
  # which fifteen minutes are spent pacing nothing.
  #
  # AND WHY THE SECOND ASK IS CONDITIONAL. `pace` reports whether it actually slept. When it
  # did not, no meaningful time passed between the two asks and the second would re-run the
  # same queries for the same answer -- a per-recipient cost on the whole audience to cover a
  # window that does not exist. When it did sleep, the first answer is stale by construction
  # and is re-taken.
  #
  # PACING CANNOT WIDEN WHAT IS PERMITTED. Every refusal `refusal` can return is re-asked
  # after the wait: the kill switch (step 1), installation revocation (step 2), blocking and
  # withdrawal in both consent stores (steps 3-7) and the missing promotional grant (step 8).
  # A degraded throttle returns :degraded and does not sleep, so there is no window to cover
  # and nothing is skipped.
  #
  # @return [Symbol, nil] nil when the send may proceed, else the refusal code
  def clear_to_send(contact, campaign, channel)
    before = refusal(contact, campaign, channel)
    return before if before

    return nil unless Campaigns::Throttle.pace(campaign.account) == :waited

    refusal(contact, campaign, channel)
  end

  # EVERY RECORD IS RE-READ, and that is the difference between this and the audience filter.
  #
  # The consent tables were always queried fresh, so a withdrawal arriving mid-run was already
  # honoured. Three other inputs were not, because they are ATTRIBUTES OF OBJECTS LOADED
  # BEFORE THE LOOP BEGAN: `campaign.account` and `campaign.commerce_store` are memoised
  # associations held for the whole job, and each contact came out of the audience relation
  # when the scheduler dispatched the campaign. Reading `settings`, `status` and `blocked` off
  # them answered a question about the moment the campaign started. So the per-account kill
  # switch, an installation revoked mid-run and an agent blocking a shopper mid-run all did
  # nothing until the next job -- the three cases this guard's whole docblock promises to
  # honour, and the only three where "now" is the only answer worth having.
  #
  # @return [Symbol, nil] nil when the send may proceed, else the refusal code
  def refusal(contact, campaign, channel)
    return :outbound_halted if Campaigns::Outbound.halted?(live(campaign.account))
    # STEP 2, AND IT IS RE-READ RATHER THAN TAKEN FROM THE HELD OBJECT, for the reason the
    # note above gives: the campaign the sender holds was loaded when the run began, and
    # cancelling is something an operator does WHILE it is running. A cancellation that only
    # took effect on the next job would be no cancellation at all, because by then there is
    # no run to stop.
    return :campaign_cancelled if live(campaign)&.cancelled?

    purpose = Campaigns::Eligibility.purpose_for(campaign)
    native = Commerce::MessagingEligibility.refusal(live(contact), purpose)
    # The memoised association decides WHETHER this is a partner-originated send, which cannot
    # change; the re-read decides whether that installation is still authorised, which can.
    return native unless campaign.commerce_store

    native_or_partner(native, contact, live(campaign.commerce_store), purpose, channel)
  end

  # A record as it is NOW, or nil when it has been deleted.
  #
  #
  # A narrow re-read by primary key rather than `reload`, because `reload` raises on a deleted
  # row and a contact deleted mid-run has to REFUSE this recipient, not abort a run that has
  # already handed messages to the provider. `Commerce::MessagingEligibility` reads nil as
  # :contact_unavailable, which is the right answer for somebody who no longer exists.
  # (A deleted store cannot reach here: `campaigns` has a foreign key to `commerce_stores`.)
  def live(record)
    record&.class&.find_by(id: record.id)
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
