require 'rails_helper'

# The money that actually arrived (custom/app/services/odoo/payment_export.rb).
RSpec.describe Odoo::PaymentExport do
  subject(:export) { described_class.new(profile, source: source, accounting: accounting) }

  include_context 'with commerce encryption'

  let(:profile) { create(:odoo_destination_profile, :registering_payments) }
  let(:source) { instance_double(Odoo::StripeSource) }
  let(:accounting) { instance_double(Odoo::Accounting) }
  let(:customer) { create(:odoo_customer_mapping, destination_profile: profile) }
  let(:invoice_mapping) do
    create(:odoo_document_mapping, :posted, destination_profile: profile, customer_mapping: customer,
                                            provider_object_id: 'in_test1', account_id: customer.account_id)
  end

  # The move as Odoo really reports it at each point: a freshly posted invoice is NOT paid, and only reads
  # paid once something has been reconciled against it. Stubbing it paid from the start would hide the
  # unknown-outcome guard rather than test it.
  def odoo_move(payment_state)
    { 'id' => 4242, 'state' => 'posted', 'payment_state' => payment_state,
      'company_id' => [profile.company_id, 'L'], 'journal_id' => [profile.journal_id, 'S'] }
  end

  before do
    allow(source).to receive(:invoice).and_return(stripe_invoice)
    allow(accounting).to receive(:register_payment).and_return(99)
    allow(accounting).to receive(:read_payment).and_return({ 'id' => 99, 'name' => 'BNK1/2026/0003' })
    # First read: the guard, before anything is registered. Later reads: the refresh afterwards, and every
    # read from then on, which is what Odoo would say once the payment exists.
    allow(accounting).to receive(:read_move).and_return(odoo_move('not_paid'), odoo_move('paid'))
  end

  it 'registers the payment for the amount Stripe reports as paid' do
    result = export.call('in_test1', invoice_mapping)

    expect(result.state).to eq(:synchronized)
    expect(accounting).to have_received(:register_payment)
      .with(hash_including(move_id: 4242, amount: BigDecimal(149)))
  end

  it 'reads the invoice payment state back from Odoo rather than asserting it' do
    export.call('in_test1', invoice_mapping)

    expect(invoice_mapping.reload.odoo_payment_state).to eq('paid')
  end

  it 'keys the payment separately from the invoice, so one cannot be mistaken for the other' do
    result = export.call('in_test1', invoice_mapping)

    expect(result.mapping.document_kind).to eq('payment')
    expect(result.mapping.idempotency_key).to include(':payment:in_test1:')
    expect(result.mapping.idempotency_key).not_to eq(invoice_mapping.idempotency_key)
  end

  it 'passes a partial payment through at the partial amount rather than rounding it up' do
    allow(source).to receive(:invoice).and_return(stripe_invoice(amount_paid: 5000))

    export.call('in_test1', invoice_mapping)

    expect(accounting).to have_received(:register_payment).with(hash_including(amount: BigDecimal(50)))
  end

  describe 'refusals' do
    it 'records nothing when Stripe reports nothing paid' do
      allow(source).to receive(:invoice).and_return(stripe_invoice(amount_paid: 0))

      expect(export.call('in_test1', invoice_mapping).state).to eq(:blocked)
      expect(accounting).not_to have_received(:register_payment)
    end

    # There is nothing to pay against until the invoice is posted.
    it 'blocks while the invoice is still a draft' do
      draft = create(:odoo_document_mapping, destination_profile: profile, odoo_record_id: 4242,
                                             odoo_state: 'draft')

      expect(export.call('in_test1', draft).reason).to eq('invoice_not_posted')
    end

    it 'blocks when the operator has not enabled payment registration' do
      # A different environment, because only one destination per environment may be enabled at a time.
      off = create(:odoo_destination_profile, :posting, environment: 'live')
      mapping = create(:odoo_document_mapping, :posted, destination_profile: off)

      result = described_class.new(off, source: source, accounting: accounting).call('in_test1', mapping)

      expect(result.reason).to eq('payment_registration_disabled')
    end
  end

  describe 'the unknown-outcome guard' do
    # An attempt may have registered the payment and died before recording its id. Registering a second one
    # would take the customer's money twice in the owner's ledger, so the invoice's own payment state is the
    # evidence and a person settles it.
    it 'refuses to register a second payment against an invoice Odoo already reads as paid' do
      result = export.call('in_test1', invoice_mapping)
      # The attempt that died before recording its id: the row looks untouched, but Odoo has the payment.
      result.mapping.update!(state: :pending, odoo_record_id: nil)
      allow(accounting).to receive(:read_move).and_return(odoo_move('paid'))

      second = export.call('in_test1', invoice_mapping)

      expect(second.state).to eq(:needs_review)
      expect(second.reason).to eq('payment_may_already_exist')
      expect(accounting).to have_received(:register_payment).once
    end

    it 'reads back a recorded payment id rather than registering again' do
      first = export.call('in_test1', invoice_mapping)
      first.mapping.update!(state: :pending)

      export.call('in_test1', invoice_mapping)

      expect(accounting).to have_received(:register_payment).once
    end

    # Our document was created for one amount and Stripe now reports another: only a person can tell a
    # redelivery from genuinely more money.
    it 'flags a change in the amount Stripe says was paid' do
      export.call('in_test1', invoice_mapping)
      allow(source).to receive(:invoice).and_return(stripe_invoice(amount_paid: 20_000))

      result = export.call('in_test1', invoice_mapping)

      expect(result.state).to eq(:needs_review)
      expect(result.reason).to include('amount_paid_changed_from_14900_to_20000')
    end
  end
end
