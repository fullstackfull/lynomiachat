require 'rails_helper'

# What this adapter actually sends to Odoo (custom/app/services/odoo/accounting.rb).
#
# EVERY EXAMPLE HERE IS A RULE FROM ODOO'S OWN SOURCE, and each one is a way the integration would otherwise be
# quietly wrong rather than loudly broken.
RSpec.describe Odoo::Accounting do
  subject(:accounting) { described_class.new(profile, client: Odoo::Client.new(profile, transport: transport)) }

  include_context 'with commerce encryption'

  let(:profile) { build(:odoo_destination_profile, id: 7, company_id: 3, journal_id: 11, payment_journal_id: 12) }
  let(:transport) { OdooRecordingTransport.new }
  let(:draft) do
    described_class::Draft.new(partner_id: 701, reference: 'LYNOMIA_CHAT/test/invoice/in_1', invoice_date: '2026-10-01',
                               currency_id: 2, lines: [{ name: 'Growth plan', quantity: 1, price_unit: 149.0 }])
  end

  def call_for(method)
    transport.call_for(method)
  end

  describe 'creating an invoice' do
    before { accounting.create_invoice(draft) }

    # account.move.move_type defaults to 'entry', so an invoice created without it is a bare journal entry.
    it 'sets move_type, because the default is a journal entry and not an invoice' do
      expect(call_for('create')[:named][:vals_list].first['move_type']).to eq('out_invoice')
    end

    # Odoo's own source: "Via RPC, it is impossible nor to use the functions nor the command constant names."
    it 'sends invoice lines as literal x2many triples, since Command helpers are Python-only' do
      lines = call_for('create')[:named][:vals_list].first['invoice_line_ids']

      expect(lines.first[0]).to eq(0)
      expect(lines.first[1]).to eq(0)
      expect(lines.first[2]).to include('name' => 'Growth plan', 'price_unit' => 149.0)
    end

    # The journal sequence assigns the number when the move leaves draft, and _compute_name will silently
    # RESET a name we pre-assigned if it does not match the move's date.
    it 'never pre-assigns the invoice number' do
      expect(call_for('create')[:named][:vals_list].first).not_to have_key('name')
    end

    # account.move.create raises UserError on any vals carrying state 'posted'.
    it 'never asks to create an already-posted move' do
      expect(call_for('create')[:named][:vals_list].first).not_to have_key('state')
    end

    # _compute_display_type turns a line with a receivable or payable account into a 'payment_term' line,
    # which silently changes the invoice's totals.
    it 'never sets account_id on a product line' do
      expect(call_for('create')[:named][:vals_list].first['invoice_line_ids'].first[2]).not_to have_key('account_id')
    end

    it 'pins the destination: our journal, our stamp, our company context' do
      vals = call_for('create')[:named][:vals_list].first

      expect(vals['journal_id']).to eq(11)
      expect(vals['ref']).to eq('LYNOMIA_CHAT/test/invoice/in_1')
      expect(call_for('create')[:context]['allowed_company_ids']).to eq([3])
    end
  end

  describe 'posting' do
    # action_post returns false and assigns the sequence number, and posting can MOVE the move's date into
    # the next open period, so the only way to know what the document became is to read it.
    it 'calls the public action_post and then reads the move back' do
      result = accounting.post_move(4242)

      expect(call_for('action_post')[:ids]).to eq([4242])
      expect(result['name']).to eq('INV/2026/0007')
      expect(call_for('read')).to be_present
    end

    it 'never calls the private _post, which Odoo refuses over RPC anyway' do
      accounting.post_move(4242)

      expect(transport.calls.map { |call| call[:method] }).not_to include('_post')
    end
  end

  describe 'registering a payment' do
    before { accounting.register_payment(move_id: 4242, amount: 149.0, payment_date: '2026-10-02', memo: 'ref') }

    # account.payment.register reads its target out of the CONTEXT, not from arguments, and default_get raises
    # if active_model names anything but account.move or account.move.line.
    it 'instantiates the wizard with active_model and active_ids in the context' do
      context = call_for('create')[:context]

      expect(context['active_model']).to eq('account.move')
      expect(context['active_ids']).to eq([4242])
    end

    it 'uses the payment journal, not the sales journal' do
      expect(call_for('create')[:named][:vals_list].first['journal_id']).to eq(12)
    end

    # With dont_redirect_to_payments, action_create_payments answers `true` and the payment's id is lost --
    # and an accounting document we cannot name is one we cannot reconcile later.
    it 'does not suppress the action response, because the payment id is in it' do
      expect(call_for('action_create_payments')[:context]).not_to have_key('dont_redirect_to_payments')
    end
  end

  describe 'what it never writes' do
    # payment_state is a stored computed field with no inverse. Odoo would most likely accept the write and
    # then overwrite it at the next recompute: the ledger would claim to be paid and then stop.
    it 'never sends payment_state in any payload' do
      accounting.create_invoice(draft)
      accounting.post_move(4242)
      accounting.register_payment(move_id: 4242, amount: 149.0, payment_date: '2026-10-02')

      # Only the WRITE payloads. Reading `payment_state` back is not merely allowed, it is the only way this
      # integration ever learns that an invoice is paid -- so the rule is about `vals_list` and `vals`, which
      # are the two keys that change anything.
      written = transport.calls.filter_map { |call| call[:named].values_at(:vals_list, :vals).compact.presence }.to_json

      expect(written).not_to include('payment_state')
      expect(written).not_to include('state')
    end
  end

  describe 'destination scope' do
    it 'scopes every search by company and journal, not by the stamp alone' do
      accounting.find_moves(reference: 'LYNOMIA_CHAT/test/invoice/in_1', move_type: 'out_invoice')

      domain = call_for('search_read')[:named][:domain]

      expect(domain).to include(['company_id', '=', 3])
      expect(domain).to include(['journal_id', '=', 11])
      expect(domain).to include(['ref', '=', 'LYNOMIA_CHAT/test/invoice/in_1'])
    end

    # A read by id is scoped by NOTHING on Odoo's side: it returns whatever that id is in any company the API
    # user can see, and in a shared Odoo that is usually several. So the row is checked before it is believed.
    it 'refuses a move that belongs to another company, whatever its id' do
      theirs = OdooRecordingTransport.new(
        'read' => [{ 'id' => 4242, 'company_id' => [9, 'Another Business'], 'journal_id' => [77, 'Theirs'] }]
      )
      other = described_class.new(profile, client: Odoo::Client.new(profile, transport: theirs))

      expect { other.read_move(4242) }.to raise_error(Odoo::Error) do |error|
        expect(error.code).to eq('CONFLICT')
        expect(error.reason).to eq('move_outside_destination_scope')
        expect(error.classification).to eq(:needs_review)
      end
    end

    # A partner with no company_id is SHARED across every company, which is how most installations hold their
    # customers -- so refusing shared partners would leave the integration unable to find any of them.
    it 'admits a shared partner, since that is how Odoo installations usually hold customers' do
      accounting.find_partners('LYNOMIA_CHAT/test/customer/account_1')

      expect(call_for('search_read')[:named][:domain]).to include(['company_id', 'in', [false, 3]])
    end
  end

  describe 'currency' do
    it 'resolves a code to a res.currency id and refuses a currency the destination has not enabled' do
      expect(accounting.currency_id('usd')).to eq(2)

      empty = described_class.new(profile, client: Odoo::Client.new(profile, transport: OdooRecordingTransport.new('search_read' => [])))
      expect { empty.currency_id('kwd') }.to raise_error(Odoo::Error, /currency_not_enabled_kwd/)
    end
  end
end
