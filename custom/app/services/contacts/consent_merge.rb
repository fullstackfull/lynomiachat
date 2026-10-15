# frozen_string_literal: true

# WHAT HAPPENS TO TWO PEOPLE'S CONSENT DECISIONS WHEN THEY TURN OUT TO BE ONE PERSON.
#
# Merging is how a duplicate contact is resolved, and until this existed it quietly destroyed
# refusals. Neither consent table appears in Contacts::MergeRelocation's SIMPLE or SCOPED
# lists, so the mergee's decisions were simply left behind on a record about to disappear: a
# shopper who had replied STOP under one of their two contact records came out of a merge
# with that STOP gone. Every protection built at the send boundary is defeated by one click
# of Merge if this is wrong.
#
# A MOVE WOULD NOT WORK EVEN IF SOMEBODY ADDED ONE. `commerce_messaging_consents` is
# UNIQUE (contact_id, purpose) and `partner_consents` is UNIQUE (store, contact, purpose,
# channel), so when both contacts hold a decision for the same scope the two rows collide.
# The question is not which row to keep but WHAT THE TWO TOGETHER MEAN.
#
# THE STRONGEST REFUSAL WINS, which is the only answer that cannot lose a refusal:
#
#   suppressed  >  withdrawn  >  granted
#
# Suppressed outranks withdrawn because it is a fact about the destination rather than a
# decision about marketing, and only an operator clears it. Withdrawn outranks granted
# because the alternative is a merge that re-permits marketing to somebody who refused it --
# and a merge is an administrative tidy-up, not a moment when anybody asked the customer
# anything.
#
# WHEN THE MERGEE'S DECISION WINS, ITS EVIDENCE COMES WITH IT. Carrying the state and leaving
# behind the source, the timestamp and the note would produce a refusal nobody could account
# for, which is the shape of record that gets overruled later by somebody who cannot see why
# it exists.
#
# IT IS NEVER A DOWNGRADE. If the base already holds the stronger decision the mergee's row
# is discarded and nothing is written, so a merge can tighten a scope or leave it alone and
# can never loosen one.
module Contacts::ConsentMerge
  RANK = { 'granted' => 0, 'withdrawn' => 1, 'suppressed' => 2 }.freeze

  module_function

  # @return [Hash] counts for the merge's audit payload
  def perform(base:, mergee:)
    { native_consents: merge_native(base, mergee), partner_consents: merge_partner(base, mergee) }.compact_blank
  end

  def merge_native(base, mergee)
    combine(Commerce::MessagingConsent.where(contact_id: mergee.id),
            Commerce::MessagingConsent.where(contact_id: base.id).index_by(&:purpose),
            base, native: true, &:purpose)
  end

  def merge_partner(base, mergee)
    combine(PartnerConsent.where(contact_id: mergee.id),
            PartnerConsent.where(contact_id: base.id).index_by { |row| partner_scope(row) },
            base, native: false) { |row| partner_scope(row) }
  end

  def partner_scope(row) = [row.commerce_store_id, row.purpose, row.channel]

  # One pass per table. Each of the mergee's rows takes one of three paths, and in every one
  # of them nothing is left pointing at the contact that is about to be deleted -- a row that
  # survives on the mergee is the defect this service exists to fix.
  #
  #   no decision on the base for that scope  ->  the row MOVES and is kept
  #   the base's decision is weaker           ->  the base's row is overwritten, this one goes
  #   the base's decision is as strong        ->  this one goes, nothing is written
  #
  # The first path keeps the row, which is why the discard below is not unconditional: an
  # earlier draft moved the row and then destroyed the row it had just moved.
  def combine(incoming, held, base, native: false)
    applied = 0

    incoming.find_each do |row|
      existing = held[yield(row)]

      if existing.nil?
        row.update!({ contact_id: base.id }.merge(revision_bump(native)))
        announce(row)
        applied += 1
        next
      end

      if overwrite(existing, row, native: native)
        announce(existing)
        applied += 1
      end
      row.destroy!
    end

    applied
  end

  def overwrite(existing, row, native: false)
    return false unless stronger?(row, existing)

    existing.update!(carried_attributes(row).merge(revision_bump(native)))
    true
  end

  # A MERGE IS A DECISION CHANGE, AND IT HAS TO LOOK LIKE ONE FROM OUTSIDE.
  #
  # This wrote `commerce_messaging_consents` directly -- the one path other than
  # Commerce::MessagingConsents.write that does -- and carried neither the revision bump nor
  # the feed publish with it. A partner therefore never learned about the change, and could
  # not learn about it afterwards either: the reconciliation pull reports the row's
  # revision, which was still the one the partner already held, and a projector drops
  # anything at or below its high-water mark.
  #
  # Concretely: the base contact is granted at revision 80 and projected as subscribed; a
  # duplicate contact holds a withdrawal because the shopper replied STOP on the number only
  # that record carried. An agent merges them -- everyday deduplication -- the strongest
  # refusal wins and the base flips to withdrawn, and the merchant's consent screen goes on
  # saying "subscribed" permanently, because 80 is not greater than 80. The drift check
  # cannot see it either: both sides read the local state as granted.
  #
  # The MOVE path publishes too. A scope the base had no row for may still have a stored
  # high-water mark from one that was cleared, and the moved row's own revision predates it.
  # BOTH TABLES, because the rule is about the merge and not about which table happens to
  # hold the row. The partner side's `revision` is already monotonic -- it is a
  # `partner_consent_events` id, one row per event -- so a merge needs no number of its
  # own there; what it needs is to be PUBLISHED, because the partner's projector will
  # otherwise go on reporting the decision it last heard about while Lynomia holds another.
  def revision_bump(native) = native ? { revision: Commerce::MessagingConsent.next_revision } : {}

  def announce(row)
    row.is_a?(PartnerConsent) ? Consents::ChangeFeed.publish_partner(row) : Consents::ChangeFeed.publish_native(row)
  end

  def stronger?(row, existing) = RANK.fetch(row.state, 0) > RANK.fetch(existing.state, 0)

  # The decision AND why it was made. `withdrawn_at` is only on the partner table.
  def carried_attributes(row)
    attributes = { :state => row.state, :source => row.source, decided_at_or_captured_at(row) => timestamp_of(row),
                   :evidence => row.evidence }
    attributes[:withdrawn_at] = row.withdrawn_at if row.respond_to?(:withdrawn_at)
    attributes
  end

  def decided_at_or_captured_at(row) = row.respond_to?(:captured_at) ? :captured_at : :decided_at

  def timestamp_of(row) = row.respond_to?(:captured_at) ? row.captured_at : row.decided_at
end
