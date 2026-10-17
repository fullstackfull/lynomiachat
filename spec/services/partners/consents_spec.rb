require 'rails_helper'

# THE PROPERTY EVERY EXAMPLE HERE DEFENDS: a delayed grant can never reactivate a withdrawal.
#
# The obvious implementation -- compare `captured_at` and let the newer win -- fails it, and
# fails it silently. `captured_at` is whatever the partner's server said: a skewed clock, a
# bug, or a caller who simply sets the field decides whether somebody who opted out gets
# marketed to. So ordering here is the EVENT'S OWN id, assigned by Postgres at insert, and
# withdrawal dominance sits on top of it: a grant cannot follow a refusal at all unless it is
# an explicit, separately verified re-consent.
RSpec.describe Partners::Consents do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:app) { create(:platform_app) }
  let(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1') }
  let(:other_store) { create(:commerce_store, account: account, provider: 'salla', external_store_id: 'sa-2') }
  let(:shopper) { create(:contact, account: account, name: 'Shopper') }

  def decision(state, ref:, **over)
    described_class::Decision.new(
      store: over.fetch(:store, store), contact: over.fetch(:contact, shopper),
      external_subject_id: 'ext-1', decision_ref: ref, state: state,
      source: over.fetch(:source, 'checkout_optin'), captured_at: over.fetch(:captured_at, Time.current),
      purpose: over.fetch(:purpose, :promotional), channel: over.fetch(:channel, :any),
      re_consent: over.fetch(:re_consent, false)
    )
  end

  def record(state, ref:, **over) = described_class.record(app: app, decision: decision(state, ref: ref, **over))

  def current(scope_store: store, purpose: :promotional, channel: :any)
    PartnerConsent.find_by(commerce_store: scope_store, contact: shopper, purpose: purpose, channel: channel)
  end

  describe 'withdrawal dominance' do
    # THE CENTRAL CASE. The grant arrives last, so any receive-order rule would apply it, and
    # it claims a later capture time, so any timestamp rule would apply it too.
    it 'refuses a later grant that arrives after a withdrawal, however new it claims to be' do
      record(:granted, ref: 'g1', captured_at: 3.days.ago)
      record(:withdrawn, ref: 'w1', captured_at: 2.days.ago)
      event = record(:granted, ref: 'g2', captured_at: 1.hour.from_now)

      expect(event.outcome).to eq(described_class::REFUSED_WITHDRAWAL_DOMINANT)
      expect(current.state).to eq('withdrawn')
    end

    it 'refuses a grant after a suppression too' do
      record(:suppressed, ref: 's1')
      event = record(:granted, ref: 'g1')

      expect(event.outcome).to eq(described_class::REFUSED_WITHDRAWAL_DOMINANT)
      expect(current.state).to eq('suppressed')
    end

    # A WRONG CLOCK MUST NOT DECIDE ANYTHING. Both of these claim to predate the withdrawal
    # and both arrive after it; neither applies.
    it 'ignores clock skew entirely, in both directions' do
      record(:withdrawn, ref: 'w1', captured_at: Time.current)
      record(:granted, ref: 'g-past', captured_at: 10.years.ago)
      record(:granted, ref: 'g-future', captured_at: 10.years.from_now)

      expect(current.state).to eq('withdrawn')
    end

    it 'keeps the refused attempts, because an ignored event is still evidence a partner tried' do
      record(:withdrawn, ref: 'w1')
      record(:granted, ref: 'g1')

      outcomes = PartnerConsentEvent.where(commerce_store: store).order(:id).pluck(:decision_ref, :outcome)
      expect(outcomes).to eq([['w1', described_class::APPLIED],
                              ['g1', described_class::REFUSED_WITHDRAWAL_DOMINANT]])
    end
  end

  describe 're-consent' do
    # A customer who changes their mind must still be able to say so, or the system would make
    # withdrawal permanent, which is not what the customer asked for either.
    it 'lets an explicit verified re-consent follow a withdrawal' do
      record(:withdrawn, ref: 'w1')
      event = record(:granted, ref: 'r1', re_consent: true, source: 'preference_centre')

      expect(event.outcome).to eq(described_class::APPLIED)
      expect(current.state).to eq('granted')
      expect(current.withdrawn_at).to be_nil
    end

    it 'leaves the whole sequence legible in the log afterwards' do
      record(:granted, ref: 'g1')
      record(:withdrawn, ref: 'w1')
      record(:granted, ref: 'r1', re_consent: true)

      expect(PartnerConsentEvent.applied.order(:id).pluck(:state)).to eq(%w[granted withdrawn granted])
    end

    # Re-consent is not a way round a provider suppression. The number is unreachable, which
    # is not a decision the customer gets to overturn -- only an operator clears it, through
    # the native path, once the cause is fixed.
    it 'still refuses a re-consent after a suppression' do
      record(:suppressed, ref: 's1')
      event = record(:granted, ref: 'r1', re_consent: true)

      expect(event.outcome).to eq(described_class::REFUSED_WITHDRAWAL_DOMINANT)
      expect(current.state).to eq('suppressed')
    end
  end

  describe 'idempotency and delivery faults' do
    it 'treats a redelivered event as a no-op and returns the event that won' do
      first = record(:granted, ref: 'g1')
      again = record(:granted, ref: 'g1')

      expect(again.id).to eq(first.id)
      expect(PartnerConsentEvent.where(decision_ref: 'g1').count).to eq(1)
    end

    it 'survives a retry storm of the same decision' do
      5.times { record(:withdrawn, ref: 'w1') }

      expect(PartnerConsentEvent.count).to eq(1)
      expect(current.state).to eq('withdrawn')
    end

    # Two partners may legitimately mint the same reference; idempotency is scoped to the
    # installation, so one cannot swallow the other's event.
    it 'scopes idempotency to the installation' do
      record(:granted, ref: 'shared-ref')
      record(:withdrawn, ref: 'shared-ref', store: other_store)

      expect(PartnerConsentEvent.count).to eq(2)
      expect(current.state).to eq('granted')
      expect(current(scope_store: other_store).state).to eq('withdrawn')
    end

    # An event whose id is below the current revision has already been superseded. This is
    # what makes a replayed backlog harmless.
    # An event whose id is below the state's current revision was assigned before the event
    # that produced that state, so it has already been superseded. This is what makes a
    # replayed backlog harmless: the state row remembers how far it has got.
    it 'drops an event that a newer one has already superseded' do
      record(:granted, ref: 'g1')
      current.update!(revision: current.revision + 1_000)

      event = record(:withdrawn, ref: 'w1')

      expect(event.outcome).to eq(described_class::SUPERSEDED)
      expect(current.state).to eq('granted')
    end
  end

  describe 'scope isolation' do
    it 'does not let a decision at one installation touch another' do
      record(:granted, ref: 'g1')
      record(:withdrawn, ref: 'w1', store: other_store)

      expect(current.state).to eq('granted')
      expect(current(scope_store: other_store).state).to eq('withdrawn')
    end

    it 'keeps purposes and channels apart' do
      record(:withdrawn, ref: 'w1', purpose: :promotional, channel: :email)
      record(:granted, ref: 'g1', purpose: :promotional, channel: :sms)

      expect(current(channel: :email).state).to eq('withdrawn')
      expect(current(channel: :sms).state).to eq('granted')
    end
  end

  # The state row is locked before it is compared, so two events for one scope cannot both
  # read the old revision and both apply. Without the lock the loser overwrites the winner.
  describe 'concurrent grant and withdrawal' do
    it 'serialises two writers and ends in one consistent state' do
      record(:granted, ref: 'g0')

      threads = [['g1', :granted], ['w1', :withdrawn]].map do |ref, state|
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { record(state, ref: ref) } }
      end
      threads.each(&:join)

      expect(current.state).to eq('withdrawn')
      expect(PartnerConsentEvent.where(decision_ref: %w[g1 w1]).count).to eq(2)
    end
  end
end
