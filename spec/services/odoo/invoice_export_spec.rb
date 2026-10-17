require 'rails_helper'

# One Stripe invoice into Odoo (custom/app/services/odoo/invoice_export.rb). The brief calls this the most
# important part of the integration, and the examples below are the ones that keep it honest.
RSpec.describe Odoo::InvoiceExport do
  subject(:export) { described_class.new(profile, source: source, accounting: accounting) }

  include_context 'with commerce encryption'

  let(:profile) { create(:odoo_destination_profile, :enabled) }
  let(:account) { create(:account) }
  let(:source) { instance_double(Odoo::StripeSource) }
  let(:accounting) { instance_double(Odoo::Accounting) }
  let(:invoice) { stripe_invoice }

  # A move as Odoo hands it back: a draft with a total, in our company and our journal.
  def odoo_move(state: 'draft', total: '149.0', name: nil)
    { 'id' => 4242, 'state' => state, 'amount_total' => total, 'name' => name,
      'payment_state' => 'not_paid', 'company_id' => [profile.company_id, 'Lynomia'],
      'journal_id' => [profile.journal_id, 'Sales'] }
  end

  before do
    allow(source).to receive(:invoice).and_return(invoice)
    allow(source).to receive(:account_for_customer).and_return(account)
    allow(accounting).to receive(:currency_id).and_return(2)
    allow(accounting).to receive(:find_partners).and_return([])
    allow(accounting).to receive(:create_partner).and_return(701)
    allow(accounting).to receive(:find_moves).and_return([])
    allow(accounting).to receive(:create_invoice).and_return(4242)
    allow(accounting).to receive(:read_move).and_return(odoo_move)
    allow(accounting).to receive(:post_move).and_return(odoo_move(state: 'posted', name: 'INV/2026/0007'))
  end

  describe 'the happy path with posting off' do
    it 'creates a DRAFT and leaves it a draft' do
      result = export.call('in_test1')

      expect(result.state).to eq(:synchronized)
      expect(result.mapping.odoo_record_id).to eq(4242)
      expect(result.mapping.odoo_state).to eq('draft')
      expect(result.mapping.odoo_document_reference).to be_nil
      expect(accounting).not_to have_received(:post_move)
    end

    it 'takes the amount from the Stripe invoice, not from a plan price' do
      create(:billing_plan, price_cents: 999_99)

      result = export.call('in_test1')

      expect(result.mapping.amount_minor).to eq(14_900)
      expect(result.mapping.currency).to eq('usd')
    end

    it 'stamps the record so it can be found again, and keys it the way the brief specifies' do
      result = export.call('in_test1')

      expect(result.mapping.source_reference).to eq("#{profile.source_app}/test/invoice/in_test1")
      expect(result.mapping.idempotency_key)
        .to eq("#{profile.source_app}:test:stripe:customer_invoice:in_test1:profile_#{profile.id}")
    end
  end

  describe 'idempotency' do
    # The case Stripe causes on its own: it documents that it may deliver an event more than once.
    it 'makes no second document on a second call' do
      first = export.call('in_test1')
      allow(accounting).to receive(:create_invoice).and_raise('must not create a second invoice')

      second = export.call('in_test1')

      expect(second.mapping.id).to eq(first.mapping.id)
      expect(Odoo::DocumentMapping.count).to eq(1)
    end

    # THE LOST-ANSWER CASE: an earlier attempt created the move and died before recording its id. Repeating the
    # write would invoice the customer twice, so Odoo is searched for our own stamp first.
    it 'adopts a move carrying our stamp instead of creating another' do
      allow(accounting).to receive(:find_moves).and_return([odoo_move])
      allow(accounting).to receive(:create_invoice).and_raise('must not create when one already exists')

      result = export.call('in_test1')

      expect(result.mapping.odoo_record_id).to eq(4242)
    end

    it 'asks a person when our stamp matches two moves rather than picking one' do
      allow(accounting).to receive(:find_moves).and_return([odoo_move, odoo_move])

      expect { export.call('in_test1') }.to raise_error(Odoo::Error, /CONFLICT/)
    end
  end

  describe 'the total comparison, which is the gate' do
    let(:profile) { create(:odoo_destination_profile, :posting) }

    it 'posts when Odoo computed the same total Stripe charged' do
      result = export.call('in_test1')

      expect(result.state).to eq(:synchronized)
      expect(result.mapping.odoo_state).to eq('posted')
      expect(result.mapping.odoo_document_reference).to eq('INV/2026/0007')
    end

    # Odoo's fiscal positions, tax mapping and rounding are the customer's, not ours. A draft whose total
    # disagrees with Stripe is never posted -- it is handed to a person.
    it 'refuses to post a draft whose total disagrees with Stripe' do
      allow(accounting).to receive(:read_move).and_return(odoo_move(total: '163.90'))

      result = export.call('in_test1')

      expect(result.state).to eq(:needs_review)
      expect(result.reason).to eq('total_mismatch_with_stripe')
      expect(accounting).not_to have_received(:post_move)
    end

    it 'tolerates one minor unit of rounding difference' do
      allow(accounting).to receive(:read_move).and_return(odoo_move(total: '148.99'))

      expect(export.call('in_test1').state).to eq(:synchronized)
    end

    # KWD is a three-decimal currency, so the tolerance has to scale with it.
    it 'scales the tolerance to a three-decimal currency' do
      allow(source).to receive(:invoice).and_return(stripe_invoice(total: 14_900, currency: 'kwd'))
      allow(accounting).to receive(:read_move).and_return(odoo_move(total: '14.899'))

      expect(export.call('in_test1').state).to eq(:synchronized)
    end
  end

  describe 'what is deliberately not exported' do
    # The brief: "A trial or manual grant must not generate fabricated revenue."
    it 'does not export a zero-amount invoice, and says why' do
      allow(source).to receive(:invoice).and_return(stripe_invoice(total: 0, amount_paid: 0))

      result = export.call('in_test1')

      expect(result.state).to eq(:blocked)
      expect(result.reason).to eq('zero_amount_not_exported')
      expect(accounting).not_to have_received(:create_invoice)
    end

    # A Stripe customer this installation never wrote is not a customer it accounts for.
    it 'does not invent a customer for an unrecognised Stripe customer' do
      allow(source).to receive(:account_for_customer).and_return(nil)

      result = export.call('in_test1')

      expect(result.state).to eq(:blocked)
      expect(result.reason).to eq('unknown_stripe_customer')
      expect(result.mapping.account_id).to be_nil
    end
  end

  describe 'invoice lines' do
    it 'maps one Odoo line per Stripe line, at Stripe\'s own amounts' do
      lines = [invoice_line(amount: 9900, description: 'Growth plan, monthly'),
               invoice_line(amount: 5000, description: 'Proration credit')]
      allow(source).to receive(:invoice).and_return(stripe_invoice(total: 14_900, lines: lines))

      export.call('in_test1')

      expect(accounting).to have_received(:create_invoice) do |draft|
        expect(draft.lines.map { |line| line[:name] }).to eq(['Growth plan, monthly', 'Proration credit'])
        expect(draft.lines.map { |line| line[:price_unit] }).to eq([BigDecimal(99), BigDecimal(50)])
      end
    end

    it 'divides a multi-quantity line so quantity times price is Stripe\'s amount' do
      lines = [invoice_line(amount: 29_800, quantity: 2, description: 'Growth plan x2')]
      allow(source).to receive(:invoice).and_return(stripe_invoice(total: 29_800, lines: lines))

      export.call('in_test1')

      expect(accounting).to have_received(:create_invoice) do |draft|
        expect(draft.lines.first[:quantity]).to eq(2)
        expect(draft.lines.first[:price_unit]).to eq(BigDecimal(149))
      end
    end

    it 'falls back to one line for the whole total when Stripe reports no lines' do
      allow(source).to receive(:invoice).and_return(stripe_invoice(lines: []))

      export.call('in_test1')

      expect(accounting).to have_received(:create_invoice) do |draft|
        expect(draft.lines.length).to eq(1)
        expect(draft.lines.first[:price_unit]).to eq(BigDecimal(149))
      end
    end
  end
end
