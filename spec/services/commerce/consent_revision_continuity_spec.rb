require 'rails_helper'

# A REVISION A PARTNER CAN RELY ON, ACROSS THE TWO PATHS THAT USED TO BREAK IT.
#
# `revision` is the whole of the partner's replay protection: a projector keeps the highest
# it has seen for a scope and drops anything at or below it. That makes every path that
# writes `commerce_messaging_consents` responsible for the number going up, and two of them
# were not.
#
#   clear_suppression  DESTROYS the row, so the next decision came from find_or_initialize_by
#                      on a fresh one and published 1 -- below every number already stored.
#   ConsentMerge       writes the row directly and carried neither a bump nor a publish, so
#                      a merge that flipped a grant to a withdrawal was invisible and stayed
#                      invisible: reconciliation reports the revision the partner already has.
#
# Both leave a partner permanently stuck on a stale state, which is the one failure mode the
# revision exists to prevent -- and in the merge case the stale state is "subscribed" for
# somebody who has opted out.
RSpec.describe 'native consent revision continuity', type: :model do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:shopper) { create(:contact, account: account) }

  def decide(contact, state, source: 'merchant')
    Commerce::MessagingConsents.record(
      account: account, contact: contact,
      decision: Commerce::MessagingConsents::Decision.new(state: state, source: source)
    )
  end

  def promotional_for(contact)
    Commerce::MessagingConsent.find_by(contact_id: contact.id, purpose: :promotional)
  end

  describe 'after a suppression is cleared' do
    it 'does not restart below what was already published' do
      decide(shopper, :suppressed)
      highest = promotional_for(shopper).revision

      Commerce::MessagingConsents.clear_suppression(account: account, contact: shopper, source: 'merchant')
      decide(shopper, :granted)

      expect(promotional_for(shopper).revision).to be > highest
    end

    # Stated over several cycles as well, because a counter that merely starts high could
    # still fall behind one that was advanced while it was gone.
    it 'keeps rising over repeated clear-and-decide cycles' do
      revisions = Array.new(3) do
        decide(shopper, :suppressed)
        taken = promotional_for(shopper).revision
        Commerce::MessagingConsents.clear_suppression(account: account, contact: shopper, source: 'merchant')
        taken
      end

      expect(revisions).to eq(revisions.sort.uniq)
    end
  end

  describe 'after a merge' do
    let(:duplicate) { create(:contact, account: account) }

    before do
      decide(shopper, :granted)
      decide(duplicate, :withdrawn)
    end

    it 'publishes the withdrawal the merge applied to the surviving contact' do
      before_revision = promotional_for(shopper).revision

      Contacts::ConsentMerge.perform(base: shopper, mergee: duplicate)

      expect(promotional_for(shopper)).to be_consent_withdrawn
      expect(promotional_for(shopper).revision).to be > before_revision
    end

    # The merge must not be able to loosen a scope, and the bump must not pretend it did.
    it 'leaves a base that already holds the stronger decision alone' do
      decide(shopper, :withdrawn)
      decide(duplicate, :granted)
      unchanged = promotional_for(shopper).revision

      Contacts::ConsentMerge.perform(base: shopper, mergee: duplicate)

      expect(promotional_for(shopper)).to be_consent_withdrawn
      expect(promotional_for(shopper).revision).to eq(unchanged)
    end

    # THE PARTNER TABLE IS A MERGE TOO. Its `revision` is already monotonic -- one row per
    # event in `partner_consent_events` -- so it needs no number of its own; what it needs
    # is to be PUBLISHED, or the partner's projector goes on reporting the decision it last
    # heard about while Lynomia holds another. The first version of this fix passed
    # `native: true` for one table and nothing for the other.
    it 'publishes the partner decision a merge moved onto the surviving contact' do
      app = create(:platform_app)
      store = create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-merge')
      PartnerConsent.create!(platform_app: app, account: account, commerce_store: store, contact: duplicate,
                             external_subject_id: 'cust-m', source: 'checkout_optin', purpose: :promotional,
                             channel: :any, state: :withdrawn, captured_at: Time.current)

      expect(Consents::ChangeFeed).to receive(:publish_partner).at_least(:once)

      Contacts::ConsentMerge.perform(base: shopper, mergee: duplicate)
    end

    # The move path: the base has no row for the scope, so the mergee's row is relocated --
    # and a scope the base once held and cleared may still have a high-water mark upstream.
    it 'raises the revision of a row it moves onto the surviving contact' do
      Commerce::MessagingConsent.where(contact_id: shopper.id).delete_all
      moved = promotional_for(duplicate)

      Contacts::ConsentMerge.perform(base: shopper, mergee: duplicate)

      expect(promotional_for(shopper).revision).to be > moved.revision
    end
  end
end
