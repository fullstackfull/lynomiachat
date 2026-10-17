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
  # An analytic account shared across companies (company_id false), which is how most installations hold one.
  let(:analytic_row) do
    { 'id' => 41, 'name' => 'Lynomia Chat', 'company_id' => false, 'plan_id' => [1, 'Projects'], 'active' => true }
  end
  let(:income_account_row) { { 'id' => 700, 'name' => 'Subscription revenue', 'code' => '4000', 'account_type' => 'income' } }
  # The rules in the destination that can change an attribution this integration did not write. None by
  # default; an example below gives the destination some.
  let(:distribution_model_rows) { [] }
  let(:move_shape) do
    { 'move_type' => { 'selection' => [%w[entry Entry], %w[out_invoice Invoice]] },
      'state' => { 'selection' => [%w[draft Draft]] },
      'payment_state' => { 'selection' => [%w[not_paid Unpaid], %w[paid Paid], %w[blocked Blocked]] },
      'ref' => {}, 'journal_id' => {}, 'company_id' => {}, 'invoice_line_ids' => {} }
  end

  before do
    allow(Odoo::Client).to receive(:new).and_return(client)
    allow(Odoo::Accounting).to receive(:new).and_return(accounting)
    # Answered PER MODEL: the shape probe asks account.move about its own fields, while the attribution probe
    # asks account.move.line whether this server has `analytic_distribution` at all. One answer for both would
    # have the attribution probe reading the invoice's field list.
    allow(client).to receive(:fields_get) do |model:, **|
      model == 'account.move.line' ? { 'analytic_distribution' => { 'type' => 'json' } } : move_shape
    end
    # Answers per journal ID, because the sales journal and the payment journal are different records with
    # different types -- a stub that returned one row for both would have the payment probe checking the
    # sales journal.
    allow(client).to receive(:search_read) do |model:, domain:, **|
      case model
      when 'res.company' then [{ 'id' => 3, 'name' => 'Lynomia FZ', 'currency_id' => [2, 'USD'] }]
      when 'account.journal' then [journal_for(domain)].compact
      when 'account.analytic.account' then [analytic_row]
      when 'account.account' then [income_account_row]
      when 'account.analytic.distribution.model' then distribution_model_rows
      else [{ 'id' => 1, 'name' => 'Row' }]
      end
    end
    allow(accounting).to receive(:create_invoice).and_return(4242)
    allow(accounting).to receive(:read_move).and_return({ 'id' => 4242, 'state' => 'draft',
                                                          'journal_id' => [11, 'Customer Invoices'] })
    allow(accounting).to receive(:read_move_lines).and_return(probe_lines)
    allow(accounting).to receive(:unlink_draft_move).and_return(true)
  end

  # The probe's own draft, as Odoo hands its journal items back: the revenue line carrying this project's
  # analytic account at 100%. This is the only honest proof that attribution works on this server.
  def probe_lines(analytic: profile.analytic_account_id)
    [{ 'id' => 7001, 'display_type' => 'product', 'name' => 'probe', 'balance' => -1.0,
       'account_id' => [700, 'Revenue'],
       'analytic_distribution' => analytic.nil? ? false : { analytic.to_s => 100.0 } }]
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

    # THE PROBE THAT CANNOT BE SKIPPED. In a company shared with sibling projects, an invoice that posts
    # perfectly but carries no analytic distribution puts this project's revenue where the owner's own reports
    # cannot separate it -- so an Odoo that cannot attribute blocks activation instead.
    describe 'attribution' do
      it 'proves attribution by reading it back off the probe draft' do
        result = diagnostics.probe_capability

        expect(result['probes']['attribution_setup']).to include('ok' => true, 'mode' => 'analytic')
        expect(result['probes']['attribution_setup']['plan']).to eq('Projects')
        expect(result['probes']['attribution']).to include('ok' => true)
        expect(result['ok']).to be(true)
      end

      # THE ONE REMAINING PATH by which the owner's own configuration can add or replace an attribution,
      # including on a PAYMENT's receivable line -- a payment is not an invoice, so Odoo's compute guard falls
      # through and runs for every line of its move. Counted, never refused: refusing a destination for having
      # distribution models would refuse most real installations.
      it 'reports how many distribution models could interfere, without refusing them' do
        expect(diagnostics.probe_capability['probes']['attribution_setup']['distribution_models']).to eq(0)
      end

      context 'when the destination has distribution models' do
        let(:distribution_model_rows) { [{ 'id' => 1 }, { 'id' => 2 }] }

        it 'counts them and still passes' do
          result = diagnostics.probe_capability

          expect(result['probes']['attribution_setup']).to include('ok' => true, 'distribution_models' => 2)
          expect(result['ok']).to be(true)
        end
      end

      it 'fails rather than skips when no analytic account names this project' do
        profile.update!(analytic_account_id: nil)

        result = diagnostics.probe_capability

        expect(result['probes']['attribution_setup']['error']['reason']).to eq('attribution_not_configured')
        expect(result['probes']['attribution']['ok']).to be(false)
        expect(result['ok']).to be(false)
      end

      it 'fails when this server has no analytic_distribution field at all' do
        allow(client).to receive(:fields_get) do |model:, **|
          model == 'account.move.line' ? {} : move_shape
        end

        result = diagnostics.probe_capability

        expect(result['probes']['attribution_setup']['error']['reason']).to eq('analytic_distribution_unsupported')
        expect(result['ok']).to be(false)
      end

      # ARCHIVING IS THE SILENT-DROP CASE: the distribution stores perfectly well and posting produces no
      # analytic line at all. The probe reads with `active_test: false` so it FINDS the archived account and
      # names the real problem instead of reporting it as missing.
      it 'fails by name when the analytic account has been archived' do
        allow(client).to receive(:search_read) do |model:, domain:, **|
          case model
          when 'res.company' then [{ 'id' => 3, 'name' => 'Lynomia FZ', 'currency_id' => [2, 'USD'] }]
          when 'account.journal' then [journal_for(domain)].compact
          when 'account.analytic.account' then [analytic_row.merge('active' => false)]
          else [{ 'id' => 1, 'name' => 'Row' }]
          end
        end

        result = diagnostics.probe_capability

        expect(result['probes']['attribution_setup']['error']['reason']).to eq('analytic_account_archived')
        expect(result['ok']).to be(false)
      end

      it 'fails when the analytic account belongs to a different company' do
        allow(client).to receive(:search_read) do |model:, domain:, **|
          case model
          when 'res.company' then [{ 'id' => 3, 'name' => 'Lynomia FZ', 'currency_id' => [2, 'USD'] }]
          when 'account.journal' then [journal_for(domain)].compact
          when 'account.analytic.account' then [analytic_row.merge('company_id' => [9, 'Another Business'])]
          else [{ 'id' => 1, 'name' => 'Row' }]
          end
        end

        result = diagnostics.probe_capability

        expect(result['probes']['attribution_setup']['error']['reason']).to eq('analytic_account_company')
        expect(result['probes']['attribution_setup']['found']).to eq('Another Business')
      end

      # The round trip is the part no configuration read can replace: it catches a distribution model in the
      # destination database replacing ours, and a revenue line reaching Odoo with nothing on it.
      it 'fails when the probe draft came back with the attribution missing' do
        allow(accounting).to receive(:read_move_lines).and_return(probe_lines(analytic: nil))

        result = diagnostics.probe_capability

        expect(result['probes']['attribution_setup']['ok']).to be(true)
        expect(result['probes']['attribution']['error']['reason']).to eq('attribution_missing')
        expect(result['ok']).to be(false)
      end

      it 'creates exactly one draft, which both the write probe and the attribution verdict read' do
        diagnostics.probe_capability

        expect(accounting).to have_received(:create_invoice).once
        expect(accounting).to have_received(:unlink_draft_move).once
      end

      context 'with the dedicated income account fallback' do
        let(:profile) do
          create(:odoo_destination_profile, :income_account_attribution, last_capability_proof: {},
                                                                         last_capability_proof_at: nil)
        end

        it 'accepts an income account and proves it on the draft' do
          allow(accounting).to receive(:read_move_lines)
            .and_return([{ 'id' => 7001, 'display_type' => 'product', 'balance' => -1.0,
                           'account_id' => [700, 'Subscription revenue'], 'analytic_distribution' => false }])

          result = diagnostics.probe_capability

          expect(result['probes']['attribution_setup']).to include('ok' => true, 'mode' => 'income_account')
          expect(result['probes']['attribution']['ok']).to be(true)
        end

        # A receivable account on a product line makes Odoo's _compute_display_type convert it into a payment
        # term: the invoice still posts and the revenue has silently vanished.
        it 'refuses an account whose type is not income' do
          allow(client).to receive(:search_read) do |model:, domain:, **|
            case model
            when 'res.company' then [{ 'id' => 3, 'name' => 'Lynomia FZ', 'currency_id' => [2, 'USD'] }]
            when 'account.journal' then [journal_for(domain)].compact
            when 'account.account' then [income_account_row.merge('account_type' => 'asset_receivable')]
            else [{ 'id' => 1, 'name' => 'Row' }]
            end
          end

          result = diagnostics.probe_capability

          expect(result['probes']['attribution_setup']['error']['reason']).to eq('income_account_type')
          expect(result['probes']['attribution_setup']['found']).to eq('asset_receivable')
        end
      end
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
