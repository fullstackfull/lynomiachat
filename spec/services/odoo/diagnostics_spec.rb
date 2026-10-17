require 'rails_helper'

# What a destination can actually do (custom/app/services/odoo/diagnostics.rb).
#
# THE BRIEF'S HARDEST POINT: "a successful login or Test Connection is NOT sufficient proof that invoice
# creation and posting work." These examples are what stop this integration claiming otherwise.
RSpec.describe Odoo::Diagnostics do
  subject(:diagnostics) { described_class.new(profile) }

  include_context 'with commerce encryption'

  let(:profile) { create(:odoo_destination_profile, last_capability_proof: {}, last_capability_proof_at: nil) }
  let(:journal_row) { { 'id' => 11, 'name' => 'Customer Invoices', 'type' => 'sale', 'code' => 'INV', 'company_id' => [3, 'Lynomia FZ'] } }
  let(:payment_journal_row) { { 'id' => 12, 'name' => 'Bank', 'type' => 'bank', 'code' => 'BNK', 'company_id' => [3, 'Lynomia FZ'] } }
  let(:client) { instance_double(Odoo::Client) }
  let(:accounting) { instance_double(Odoo::Accounting) }

  before do
    allow(Odoo::Client).to receive(:new).and_return(client)
    allow(Odoo::Accounting).to receive(:new).and_return(accounting)
    allow(client).to receive(:fields_get).and_return(
      'move_type' => { 'selection' => [%w[entry Entry], %w[out_invoice Invoice]] },
      'state' => { 'selection' => [%w[draft Draft]] },
      'payment_state' => { 'selection' => [%w[not_paid Unpaid], %w[paid Paid], %w[blocked Blocked]] },
      'ref' => {}, 'journal_id' => {}, 'company_id' => {}, 'invoice_line_ids' => {}
    )
    # Answers per journal ID, because the sales journal and the payment journal are different records with
    # different types -- a stub that returned one row for both would have the payment probe checking the
    # sales journal.
    allow(client).to receive(:search_read) do |model:, domain:, **|
      case model
      when 'res.company' then [{ 'id' => 3, 'name' => 'Lynomia FZ', 'currency_id' => [2, 'USD'] }]
      when 'account.journal' then [journal_for(domain)].compact
      else [{ 'id' => 1, 'name' => 'Row' }]
      end
    end
    allow(accounting).to receive(:create_invoice).and_return(4242)
    allow(accounting).to receive(:read_move).and_return({ 'id' => 4242, 'state' => 'draft',
                                                          'journal_id' => [11, 'Customer Invoices'] })
    allow(accounting).to receive(:unlink_draft_move).and_return(true)
  end

  def journal_for(domain)
    requested = domain.find { |condition| condition.first == 'id' }&.last
    requested == 12 ? payment_journal_row : journal_row
  end

  describe 'the connection test' do
    before do
      allow(Odoo::VersionProbe).to receive(:new).and_return(
        instance_double(Odoo::VersionProbe,
                        call: Odoo::VersionProbe::Result.new(ok: true, major: 19, version: '19.0',
                                                             info: { 'server_version' => '19.0' }, transport: 'json2'))
      )
    end

    it 'stores the detected version and transport so nothing later has to guess' do
      result = diagnostics.test_connection

      expect(result['ok']).to be(true)
      expect(profile.reload.odoo_version).to eq('19.0')
      expect(profile.transport).to eq('json2')
    end

    it 'reports the stage it failed at rather than a bare false' do
      allow(Odoo::VersionProbe).to receive(:new).and_return(
        instance_double(Odoo::VersionProbe,
                        call: Odoo::VersionProbe::Result.new(ok: false, error: { 'code' => 'UNREACHABLE' }))
      )

      result = diagnostics.test_connection

      expect(result['stage']).to eq('version')
      expect(result['error']['code']).to eq('UNREACHABLE')
    end

    it 'never puts a credential in the stored result' do
      diagnostics.test_connection

      expect(profile.reload.last_connection_result.to_json).not_to include('odoo-api-key-factory')
    end
  end

  describe 'the capability probe' do
    it 'passes every probe and reads the payment states this server actually has' do
      result = diagnostics.probe_capability

      expect(result['ok']).to be(true)
      # Odoo 18 added 'blocked' to payment_state, so its selection IS the version branch -- read from the
      # server rather than inferred from a version number.
      expect(result['probes']['model_shape']['payment_states']).to include('blocked')
      expect(result['probes']['sale_journal']).to include('ok' => true, 'type' => 'sale')
    end

    # THE ONE WRITE, AND ITS UNDOING. A draft has no sequence number, so deleting one leaves no accounting
    # trace and no gap in the customer's numbering.
    it 'creates a draft, reads it back, and deletes it' do
      result = diagnostics.probe_capability

      expect(accounting).to have_received(:create_invoice).once
      expect(accounting).to have_received(:unlink_draft_move).with(4242)
      expect(result['probes']['draft_create']).to include('ok' => true, 'removed' => true)
    end

    # POSTING IS NOT PROVEN AND IS NOT CLAIMED TO BE: proving it would leave a permanently numbered document
    # in somebody else's books.
    it 'reports posting as unproven even when every probe passes' do
      expect(diagnostics.probe_capability['posting']).to eq('unproven')
    end

    it 'catches a journal that is not a sales journal' do
      allow(client).to receive(:search_read) do |model:, domain:, **|
        model == 'account.journal' ? [journal_for(domain).merge('type' => 'general')] : [{ 'id' => 3, 'name' => 'X' }]
      end

      result = diagnostics.probe_capability

      expect(result['ok']).to be(false)
      expect(result['probes']['sale_journal']['error']['reason']).to eq('journal_type')
    end

    # THE ISOLATION FAILURE THIS WHOLE INTEGRATION EXISTS TO PREVENT: a journal in the wrong company would
    # post Lynomia's revenue into another business's books.
    it 'catches a journal that belongs to another company' do
      allow(client).to receive(:search_read) do |model:, domain:, **|
        model == 'account.journal' ? [journal_for(domain).merge('company_id' => [9, 'Another Business'])] : [{ 'id' => 3, 'name' => 'X' }]
      end

      result = diagnostics.probe_capability

      expect(result['probes']['sale_journal']['error']['reason']).to eq('journal_company')
      expect(result['probes']['sale_journal']['found']).to eq('Another Business')
    end

    # Analytic accounting is not in every Odoo edition and version, so requiring one would make the
    # integration unusable where there is nothing to pick.
    it 'skips the analytic account when none is configured, rather than failing' do
      result = diagnostics.probe_capability

      expect(result['probes']['analytic_account']).to include('skipped' => true)
      expect(result['ok']).to be(true)
    end

    it 'reports each probe separately so one failure does not hide the rest' do
      allow(accounting).to receive(:create_invoice).and_raise(Odoo::Error.new('PERMISSION_DENIED'))

      result = diagnostics.probe_capability

      expect(result['probes']['draft_create']['error']['code']).to eq('PERMISSION_DENIED')
      expect(result['probes']['company']['ok']).to be(true)
      expect(result['ok']).to be(false)
    end

    it 'refuses to probe at all before the destination scope is chosen' do
      profile.update!(journal_id: nil)

      expect(diagnostics.probe_capability['error']['reason']).to eq('scope_incomplete')
    end
  end
end
