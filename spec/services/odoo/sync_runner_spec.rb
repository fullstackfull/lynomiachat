require 'rails_helper'

# The queue's state machine (custom/app/services/odoo/sync_runner.rb).
RSpec.describe Odoo::SyncRunner do
  include_context 'with commerce encryption'

  let(:profile) { create(:odoo_destination_profile, :enabled) }
  let(:event) { create(:odoo_sync_event, destination_profile: profile, provider_object_id: 'in_test1') }
  let(:source) { instance_double(Odoo::StripeSource) }
  let(:accounting) { instance_double(Odoo::Accounting) }

  def runner(for_event = event)
    described_class.new(for_event, source: source, accounting: accounting)
  end

  def exporting(state, mapping: nil, reason: nil)
    allow(Odoo::InvoiceExport).to receive(:new).and_return(
      instance_double(Odoo::InvoiceExport,
                      call: Odoo::InvoiceExport::Result.new(state: state, mapping: mapping, reason: reason))
    )
  end

  describe 'claiming' do
    # TWO WORKERS, ONE ROW. The claim is one conditional UPDATE, so the database picks the winner and the
    # loser does nothing -- no lock, no Redis.
    it 'lets exactly one of two concurrent runners do the work' do
      exporting(:synchronized)
      first = runner(Odoo::SyncEvent.find(event.id))
      second = runner(Odoo::SyncEvent.find(event.id))

      first.call
      second.call

      expect(event.reload.attempts_count).to eq(1)
      expect(event.attempts.count).to eq(1)
    end

    it 'does not pick up a row that is already synchronized' do
      event.update!(state: :synchronized)
      allow(Odoo::InvoiceExport).to receive(:new).and_raise('must not export a finished row')

      expect { runner.call }.not_to raise_error
    end
  end

  describe 'gates' do
    it 'blocks rather than exporting when the destination is switched off' do
      profile.update!(sync_enabled: false)
      allow(Odoo::InvoiceExport).to receive(:new).and_raise('must not export while disabled')

      runner.call

      expect(event.reload).to be_state_blocked
      expect(event.blocked_reason).to eq('destination_not_enabled')
    end

    it 'blocks an object type it does not handle instead of silently doing nothing' do
      odd = create(:odoo_sync_event, destination_profile: profile, provider_object_type: 'coupon')

      runner(odd).call

      expect(odd.reload.blocked_reason).to eq('unhandled_object_type_coupon')
    end
  end

  describe 'outcomes' do
    it 'marks the row synchronized and stamps when it finished' do
      exporting(:synchronized)

      runner.call

      expect(event.reload).to be_state_synchronized
      expect(event.completed_at).to be_present
      expect(event.attempts.first.outcome).to eq(Odoo::SyncAttempt::SUCCEEDED)
    end

    # The attempt row is written BEFORE the call goes out, which is what lets a later attempt tell a crash
    # mid-write from a write that never happened.
    it 'records the attempt before the export runs' do
      allow(Odoo::InvoiceExport).to receive(:new) do
        expect(event.reload.attempts.count).to eq(1)
        instance_double(Odoo::InvoiceExport, call: Odoo::InvoiceExport::Result.new(state: :synchronized))
      end

      runner.call
    end

    it 'schedules another attempt for a transient failure, with backoff' do
      allow(Odoo::InvoiceExport).to receive(:new).and_raise(Odoo::Error.new('SERVER_ERROR', reason: 'http_502'))

      runner.call

      expect(event.reload).to be_state_retrying
      expect(event.run_after).to be > Time.current
      expect(event.claimed_at).to be_nil
      expect(event.attempts.first.outcome).to eq(Odoo::SyncAttempt::TRANSIENT)
    end

    it 'fails a permanent error without retrying it' do
      allow(Odoo::InvoiceExport).to receive(:new).and_raise(Odoo::Error.new('BUSINESS_RULE', reason: 'UserError'))

      runner.call

      expect(event.reload).to be_state_failed
      expect(event.last_error_class).to eq('BUSINESS_RULE')
      expect(event.attempts.first.outcome).to eq(Odoo::SyncAttempt::PERMANENT)
    end

    it 'stops retrying once the attempts are exhausted' do
      allow(Odoo::InvoiceExport).to receive(:new).and_raise(Odoo::Error.new('SERVER_ERROR'))
      event.update!(attempts_count: Odoo::SyncEvent::MAX_ATTEMPTS)

      runner.call

      expect(event.reload).to be_state_failed
    end

    it 'routes a record Odoo no longer has to a person rather than retrying it' do
      allow(Odoo::InvoiceExport).to receive(:new).and_raise(Odoo::Error.new('RECORD_MISSING', reason: 'move_gone'))

      runner.call

      expect(event.reload).to be_state_needs_review
    end

    it 'routes a customer conflict to a person' do
      allow(Odoo::InvoiceExport).to receive(:new)
        .and_raise(Odoo::CustomerResolver::Conflict, 'partner_claimed_by_another_account')

      runner.call

      expect(event.reload).to be_state_needs_review
      expect(event.attempts.first.reason).to eq('partner_claimed_by_another_account')
    end

    it 'blocks when Stripe is not configured, because there is nothing to read' do
      allow(Odoo::InvoiceExport).to receive(:new).and_raise(Odoo::StripeSource::NotConfigured)

      runner.call

      expect(event.reload.blocked_reason).to eq('stripe_not_configured')
    end
  end

  describe 'payments following an invoice' do
    let(:mapping) { create(:odoo_document_mapping, :posted, destination_profile: profile) }

    it 'exports the payment in the same pass once the invoice is posted' do
      exporting(:synchronized, mapping: mapping)
      payment = instance_double(Odoo::PaymentExport, call: Odoo::PaymentExport::Result.new(state: :synchronized))
      allow(Odoo::PaymentExport).to receive(:new).and_return(payment)

      runner.call

      expect(payment).to have_received(:call).with('in_test1', mapping)
    end

    it 'does not try to pay an invoice that is still a draft' do
      exporting(:synchronized, mapping: create(:odoo_document_mapping, destination_profile: profile))
      allow(Odoo::PaymentExport).to receive(:new).and_raise('must not pay a draft')

      expect { runner.call }.not_to raise_error
    end
  end

  describe 'a dispute' do
    let(:event) { create(:odoo_sync_event, destination_profile: profile, provider_object_type: 'dispute', event_type: 'charge.dispute.created') }

    # A chargeback's accounting treatment differs by jurisdiction and by the owner's own policy, so nothing is
    # written to Odoo and a person decides.
    it 'writes nothing to Odoo and asks a person' do
      runner.call

      expect(event.reload).to be_state_needs_review
      expect(Odoo::DocumentMapping.count).to eq(0)
    end
  end
end
