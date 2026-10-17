require 'rails_helper'

# Bringing past Stripe invoices in, on purpose (custom/app/services/odoo/historical_import.rb).
RSpec.describe Odoo::HistoricalImport do
  subject(:import) { described_class.new(profile, source: source) }

  include_context 'with commerce encryption'

  let(:profile) { create(:odoo_destination_profile, :enabled) }
  let(:source) { instance_double(Odoo::StripeSource) }
  let(:account) { create(:account) }
  let(:window) { [30.days.ago, Time.current] }

  def listing(invoices, has_more: false)
    Stripe::ListObject.construct_from(object: 'list', has_more: has_more,
                                      data: invoices.map(&:to_hash))
  end

  before do
    allow(source).to receive(:account_for_customer).and_return(account)
    allow(source).to receive(:invoices_in_period).and_return(listing([stripe_invoice(id: 'in_a'),
                                                                      stripe_invoice(id: 'in_b')]))
  end

  describe 'the preview' do
    # THE PREVIEW WRITES NOTHING. An operator sees the number before they cause it.
    it 'reads and counts without creating anything at all' do
      expect { import.preview(from: window.first, to: window.last) }
        .to not_change(Odoo::SyncEvent, :count).and not_change(Odoo::DocumentMapping, :count)
    end

    it 'reports what would be exported, and the money involved' do
      preview = import.preview(from: window.first, to: window.last)

      expect(preview.total).to eq(2)
      expect(preview.exportable).to eq(2)
      expect(preview.by_currency).to eq({ 'USD' => 29_800 })
    end

    it 'separates the invoices it would skip, with the reason in its own count' do
      allow(source).to receive(:invoices_in_period).and_return(
        listing([stripe_invoice(id: 'in_a'), stripe_invoice(id: 'in_zero', total: 0),
                 stripe_invoice(id: 'in_orphan', customer: 'cus_unknown')])
      )
      allow(source).to receive(:account_for_customer) { |id| id == 'cus_unknown' ? nil : account }

      preview = import.preview(from: window.first, to: window.last)

      expect(preview.total).to eq(3)
      expect(preview.exportable).to eq(1)
      expect(preview.zero_amount).to eq(1)
      expect(preview.unknown_customer).to eq(1)
    end

    it 'counts an invoice this installation has already exported as already exported' do
      create(:odoo_document_mapping, destination_profile: profile, provider_object_id: 'in_a',
                                     state: :synchronized)

      preview = import.preview(from: window.first, to: window.last)

      expect(preview.already_exported).to eq(1)
      expect(preview.exportable).to eq(1)
    end

    # A count an operator cannot trust is worse than a count that says it is incomplete.
    it 'says so when the window holds more invoices than one preview reads' do
      allow(source).to receive(:invoices_in_period).and_return(listing([stripe_invoice], has_more: true))

      expect(import.preview(from: window.first, to: window.last).truncated).to be(true)
    end
  end

  describe 'the confirmed import' do
    it 'enqueues one row per exportable invoice, marked as a backfill' do
      expect { import.confirm!(from: window.first, to: window.last) }
        .to change(Odoo::SyncEvent, :count).by(2)

      expect(Odoo::SyncEvent.pluck(:origin)).to all(eq('backfill'))
      expect(Odoo::SyncEvent.pluck(:event_type)).to all(eq('backfill.invoice'))
    end

    it 'writes nothing to Odoo in the request, only queues work' do
      expect { import.confirm!(from: window.first, to: window.last) }
        .to have_enqueued_job(Odoo::SyncJob).twice
    end

    # THE IDEMPOTENCY ENGINE IS SHARED, which is what makes running this twice harmless.
    it 'queues nothing new the second time it is run over the same window' do
      expect(import.confirm!(from: window.first, to: window.last)).to eq(2)

      expect(import.confirm!(from: window.first, to: window.last)).to eq(0)
      expect(Odoo::SyncEvent.count).to eq(2)
    end

    # The brief: a backfill must not be able to produce a second document for something live sync handled.
    it 'collapses onto the row live synchronisation already made for the same invoice' do
      live = Odoo::EventRecorder.new(profile, source: source)
                                .record_backfill(provider_object_type: 'invoice', provider_object_id: 'in_a',
                                                 event_type: 'invoice.paid')
      live.update!(origin: 'webhook')

      import.confirm!(from: window.first, to: window.last)

      expect(Odoo::SyncEvent.where(provider_object_id: 'in_a').count).to eq(1)
      expect(Odoo::SyncEvent.find_by(provider_object_id: 'in_a').origin).to eq('webhook')
    end

    it 'skips a zero-amount invoice and one with no matching customer' do
      allow(source).to receive(:invoices_in_period).and_return(
        listing([stripe_invoice(id: 'in_zero', total: 0), stripe_invoice(id: 'in_orphan')])
      )
      allow(source).to receive(:account_for_customer).and_return(nil)

      expect { import.confirm!(from: window.first, to: window.last) }.not_to change(Odoo::SyncEvent, :count)
    end
  end
end
