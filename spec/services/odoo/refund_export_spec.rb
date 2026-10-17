require 'rails_helper'

# A Stripe refund as an Odoo credit note (custom/app/services/odoo/refund_export.rb).
#
# TWO DIFFERENT ODOO OPERATIONS, because Odoo 17 removed the wizard's `refund_method` field: `reverse_moves`
# now reverses the whole move and has no amount anywhere in it, so a partial refund has to be a directly
# created out_refund.
RSpec.describe Odoo::RefundExport do
  subject(:export) { described_class.new(profile, source: source, accounting: accounting) }

  include_context 'with commerce encryption'

  let(:profile) { create(:odoo_destination_profile, :posting) }
  let(:source) { instance_double(Odoo::StripeSource) }
  let(:accounting) { instance_double(Odoo::Accounting) }
  let(:customer) { create(:odoo_customer_mapping, destination_profile: profile) }
  let(:invoice_mapping) do
    create(:odoo_document_mapping, :posted, destination_profile: profile, customer_mapping: customer,
                                            amount_minor: 14_900, currency: 'usd')
  end

  def credit_note(state: 'posted')
    { 'id' => 5555, 'state' => state, 'name' => 'RINV/2026/0002',
      'company_id' => [profile.company_id, 'L'], 'journal_id' => [profile.journal_id, 'S'] }
  end

  before do
    allow(accounting).to receive(:currency_id).and_return(2)
    allow(accounting).to receive(:reverse_move).and_return(5555)
    allow(accounting).to receive(:create_partial_credit_note).and_return(5555)
    allow(accounting).to receive(:read_move).and_return(credit_note)
    allow(accounting).to receive(:post_move).and_return(credit_note)
  end

  describe 'a full refund' do
    before { allow(source).to receive(:refund).and_return(stripe_refund(amount: 14_900)) }

    it 'reverses the invoice through Odoo\'s own reversal wizard' do
      result = export.call('rf_test1', invoice_mapping)

      expect(result.state).to eq(:synchronized)
      expect(accounting).to have_received(:reverse_move).with(hash_including(move_id: 4242))
      expect(accounting).not_to have_received(:create_partial_credit_note)
      expect(result.mapping.odoo_document_reference).to eq('RINV/2026/0002')
    end

    # Odoo creates a reversal dated in the future with auto_post 'at_date', so its state is read rather than
    # assumed.
    it 'records the state Odoo reports rather than assuming posted' do
      allow(accounting).to receive(:read_move).and_return(credit_note(state: 'draft'))

      result = export.call('rf_test1', invoice_mapping)

      expect(result.mapping.odoo_state).to eq('draft')
      expect(result.mapping.posted_at).to be_nil
    end
  end

  describe 'a partial refund' do
    before { allow(source).to receive(:refund).and_return(stripe_refund(amount: 5000)) }

    it 'creates an out_refund for the credited amount and links it to the invoice' do
      export.call('rf_test1', invoice_mapping)

      expect(accounting).to have_received(:create_partial_credit_note) do |draft, reversed_entry_id:|
        expect(draft.lines.first[:price_unit]).to eq(BigDecimal(50))
        expect(reversed_entry_id).to eq(4242)
      end
      expect(accounting).not_to have_received(:reverse_move)
    end

    # DELIBERATE, and stated in the UI: reconciling a partial credit note decides whether the invoice reads
    # partial or paid, and a wrong guess misstates a ledger this integration does not own.
    it 'leaves the reconciliation to a person and says so' do
      result = export.call('rf_test1', invoice_mapping)

      expect(result.state).to eq(:needs_review)
      expect(result.reason).to eq('partial_credit_note_awaiting_reconciliation')
    end
  end

  describe 'refusals and idempotency' do
    before { allow(source).to receive(:refund).and_return(stripe_refund(amount: 14_900)) }

    it 'makes no second credit note for the same refund' do
      export.call('rf_test1', invoice_mapping)
      allow(accounting).to receive(:reverse_move).and_raise('must not reverse twice')

      export.call('rf_test1', invoice_mapping)

      expect(Odoo::DocumentMapping.where(document_kind: 'credit_note').count).to eq(1)
    end

    it 'gives each refund against one invoice its own credit note' do
      export.call('rf_test1', invoice_mapping)
      allow(source).to receive(:refund).and_return(stripe_refund(id: 'rf_test2', amount: 5000))

      export.call('rf_test2', invoice_mapping)

      expect(Odoo::DocumentMapping.where(document_kind: 'credit_note').count).to eq(2)
    end

    it 'blocks when the invoice was never posted' do
      draft = create(:odoo_document_mapping, destination_profile: profile, odoo_record_id: 4242,
                                             odoo_state: 'draft')

      expect(export.call('rf_test1', draft).reason).to eq('invoice_not_posted')
    end

    it 'blocks when posting is off, because a credit note has to be posted to mean anything' do
      # A different environment: only one destination per environment may be enabled at a time.
      off = create(:odoo_destination_profile, :enabled, environment: 'live')
      mapping = create(:odoo_document_mapping, :posted, destination_profile: off)

      result = described_class.new(off, source: source, accounting: accounting).call('rf_test1', mapping)

      expect(result.reason).to eq('posting_disabled')
    end
  end
end
