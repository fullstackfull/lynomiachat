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

  # `reversed_entry_id` points at OUR invoice, which is how a credit note Odoo authored is tied to this
  # integration: Odoo writes its own "Reversal of: ..." into `ref`, so our stamp is not there to match, and in
  # a company shared with sibling projects the company and journal identify nothing.
  def credit_note(state: 'posted', reversed: 4242, ref: nil)
    { 'id' => 5555, 'state' => state, 'name' => 'RINV/2026/0002', 'ref' => ref,
      'reversed_entry_id' => reversed.nil? ? false : [reversed, 'INV/2026/0007'],
      'company_id' => [profile.company_id, 'L'], 'journal_id' => [profile.journal_id, 'S'] }
  end

  # A credit note's journal items: the revenue reversal carries this project's analytic account, mirroring the
  # invoice it credits. Odoo copies the source line's distribution onto a reversal because the mixin field is
  # copy=True, so the happy path needs no repair -- but it is READ rather than trusted.
  def credit_lines(analytic: profile.analytic_account_id)
    [{ 'id' => 6001, 'display_type' => 'product', 'name' => 'Refund', 'balance' => 149.0,
       'account_id' => [700, 'Revenue'],
       'analytic_distribution' => analytic.nil? ? false : { analytic.to_s => 100.0 } }]
  end

  before do
    allow(accounting).to receive(:currency_id).and_return(2)
    allow(accounting).to receive(:reverse_move).and_return(5555)
    allow(accounting).to receive(:create_partial_credit_note).and_return(5555)
    allow(accounting).to receive(:read_move).and_return(credit_note)
    allow(accounting).to receive(:read_move_lines).and_return(credit_lines)
    allow(accounting).to receive(:apply_attribution)
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

  # REQUIREMENT: a credit note is attributed to the SAME project as the invoice it credits. The two cases get
  # there differently -- Odoo copies the lines on a reversal, we author them on a partial -- so both are
  # checked, and the reversal is repaired rather than trusted.
  describe 'attribution carried onto the credit note' do
    before { allow(source).to receive(:refund).and_return(stripe_refund(amount: 14_900)) }

    it 'records the same project attribution as the invoice, confirmed by a read' do
      result = export.call('rf_test1', invoice_mapping)

      expect(result.mapping.odoo_analytic_account_id).to eq(profile.analytic_account_id)
      expect(result.mapping.attribution_verified_at).to be_present
      expect(accounting).not_to have_received(:apply_attribution)
    end

    # Odoo authored these lines. If the distribution did not come across and the reversal is still a draft,
    # writing it on is correct: it is our own credit note for our own invoice, and a draft is not yet a legal
    # record.
    it 'writes the attribution onto a draft reversal that came back without it' do
      allow(accounting).to receive(:read_move).and_return(credit_note(state: 'draft'))
      # Two reads, not three: the repair reuses the lines from the first read to pick the revenue line ids, so
      # the second read is the verification of what the write achieved.
      allow(accounting).to receive(:read_move_lines).and_return(credit_lines(analytic: nil), credit_lines)

      result = export.call('rf_test1', invoice_mapping)

      expect(accounting).to have_received(:apply_attribution).with([6001])
      expect(result.mapping.attribution_verified_at).to be_present
    end

    # A POSTED journal item is the legal record. It is reversed, never rewritten -- so this is reported rather
    # than corrected.
    it 'asks a person when a reversal Odoo already posted came back unattributed' do
      allow(accounting).to receive(:read_move_lines).and_return(credit_lines(analytic: nil))

      result = export.call('rf_test1', invoice_mapping)

      expect(result.state).to eq(:needs_review)
      expect(result.reason).to eq('attribution_missing')
      expect(accounting).not_to have_received(:apply_attribution)
    end

    # OWNERSHIP, not company. Odoo writes its own "Reversal of: ..." into the credit note's ref, so the only
    # exact link back to this integration is the id of the move it reverses.
    it 'refuses a reversal that is not linked to our own invoice' do
      allow(accounting).to receive(:read_move).and_return(credit_note(reversed: 99_999))

      expect { export.call('rf_test1', invoice_mapping) }
        .to raise_error(Odoo::Error) { |error| expect(error.reason).to eq('reversal_not_linked_to_our_invoice') }
    end

    context 'with a partial refund, whose lines this integration authors' do
      before { allow(source).to receive(:refund).and_return(stripe_refund(amount: 5_000)) }

      it 'checks the attribution BEFORE posting, so an unattributed credit note is never made permanent' do
        allow(accounting).to receive(:read_move_lines).and_return(credit_lines(analytic: nil))

        result = export.call('rf_test2', invoice_mapping)

        expect(result.state).to eq(:needs_review)
        expect(result.reason).to eq('attribution_missing')
        expect(accounting).not_to have_received(:post_move)
      end
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
