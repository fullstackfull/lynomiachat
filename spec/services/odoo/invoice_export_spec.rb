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

  # The journal items as Odoo hands them back: one revenue line carrying this project's analytic account at
  # 100%, and the receivable, which must NOT carry it. Attribution is read back rather than assumed, so every
  # example needs an answer for it.
  def odoo_lines(analytic: profile.analytic_account_id, share: 100.0)
    [{ 'id' => 5001, 'display_type' => 'product', 'name' => 'Growth plan', 'balance' => -149.0,
       'account_id' => [700, 'Revenue'],
       'analytic_distribution' => analytic.nil? ? false : { analytic.to_s => share } },
     { 'id' => 5002, 'display_type' => 'payment_term', 'name' => 'Receivable', 'balance' => 149.0,
       'account_id' => [120, 'Debtors'], 'analytic_distribution' => false }]
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
    allow(accounting).to receive(:read_move_lines).and_return(odoo_lines)
    # The analytic ledger Odoo builds at posting. One row per revenue line is the proof that the distribution
    # produced attribution rather than merely being stored.
    allow(accounting).to receive(:read_analytic_lines).and_return([{ 'id' => 8001, 'amount' => 149.0,
                                                                     'move_line_id' => [5001, 'Growth plan'] }])
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

  # THE SECOND GATE, and the one a company shared with sibling projects adds. Sending the attribution is not
  # evidence that it landed: Odoo computes `analytic_distribution` where none was supplied, and an
  # `account.analytic.distribution.model` rule in the destination database can replace the one we sent.
  describe 'the attribution gate' do
    let(:profile) { create(:odoo_destination_profile, :posting) }

    it 'records what the document was attributed to, and that the attribution was confirmed by a read' do
      result = export.call('in_test1')

      expect(result.state).to eq(:synchronized)
      expect(result.mapping.attribution_mode).to eq(Odoo::Attribution::ANALYTIC)
      expect(result.mapping.odoo_analytic_account_id).to eq(profile.analytic_account_id)
      expect(result.mapping.attribution_verified_at).to be_present
    end

    it 'refuses to post, and asks a person, when the revenue line came back unattributed' do
      allow(accounting).to receive(:read_move_lines).and_return(odoo_lines(analytic: nil))

      result = export.call('in_test1')

      expect(result.state).to eq(:needs_review)
      expect(result.reason).to eq('attribution_missing')
      expect(accounting).not_to have_received(:post_move)
      expect(result.mapping.attribution_verified_at).to be_nil
    end

    it 'refuses to post when the revenue line came back attributed to another project' do
      allow(accounting).to receive(:read_move_lines).and_return(odoo_lines(analytic: 77))

      result = export.call('in_test1')

      expect(result.state).to eq(:needs_review)
      expect(result.reason).to eq('attribution_foreign_analytic_account')
      expect(accounting).not_to have_received(:post_move)
    end

    it 'refuses to post when only part of the line was attributed to this project' do
      allow(accounting).to receive(:read_move_lines).and_return(odoo_lines(share: 60.0))

      result = export.call('in_test1')

      expect(result.state).to eq(:needs_review)
      expect(result.reason).to eq('attribution_partial')
      expect(accounting).not_to have_received(:post_move)
    end

    # THE SILENT-DROP CASE. If the distribution names an analytic account that has since been archived or
    # deleted, Odoo stores it, posts the invoice, creates NO analytic line and raises nothing -- so the
    # revenue is posted attributed to nobody. The stored distribution cannot show this; only the ledger can.
    it 'refuses to call a posted invoice synchronized when Odoo created no analytic line from it' do
      allow(accounting).to receive(:read_analytic_lines).and_return([])

      result = export.call('in_test1')

      expect(result.state).to eq(:needs_review)
      expect(result.reason).to eq('analytic_lines_not_created')
      # The invoice IS posted -- a posted document is reversed, never withdrawn -- and that is recorded
      # honestly rather than hidden.
      expect(result.mapping.odoo_state).to eq('posted')
      expect(result.mapping.attribution_verified_at).to be_nil
    end

    it 'does not look for an analytic ledger in the dedicated-income-account mode, which has none' do
      profile.update!(attribution_mode: Odoo::Attribution::INCOME_ACCOUNT, analytic_account_id: nil,
                      income_account_id: 700)
      allow(accounting).to receive(:read_move_lines)
        .and_return([{ 'id' => 5001, 'display_type' => 'product', 'balance' => -149.0,
                       'account_id' => [700, 'Revenue'], 'analytic_distribution' => false }])

      expect(export.call('in_test1').state).to eq(:synchronized)
      expect(accounting).not_to have_received(:read_analytic_lines)
    end

    # The total gate runs FIRST, because a wrong amount is the more consequential of the two and an operator
    # reading one reason should be reading the one that matters most.
    it 'reports the total mismatch rather than the attribution when both are wrong' do
      allow(accounting).to receive(:read_move).and_return(odoo_move(total: '999.0'))
      allow(accounting).to receive(:read_move_lines).and_return(odoo_lines(analytic: nil))

      expect(export.call('in_test1').reason).to eq('total_mismatch_with_stripe')
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
