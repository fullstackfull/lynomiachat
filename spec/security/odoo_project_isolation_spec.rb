require 'rails_helper'

# TWO UNRELATED PROJECTS INSIDE ONE ODOO COMPANY.
#
# The destination Odoo holds ONE legal company. Lynomia Chat is one project in it; "Atlas Logistics" below is
# another, belonging to the same owner and nothing to do with Lynomia Chat. They share the company id. They
# share the sales journal. Their customers share names and billing emails, and their invoice numbers collide.
# Odoo provides no record-level isolation between them: the only record rule on an analytic account is
# company-based, and within one company every analytic account is readable and writable by the same API user.
#
# So every guarantee asserted here has to come from this integration's own code, and the fake Odoo it runs
# against (spec/support/odoo_shared_company.rb) is deliberately permissive -- it answers searches honestly
# from a shared table holding both projects' rows. Anything that leaks, leaks here.
# rubocop:disable RSpec/DescribeClass -- the subject is the GUARANTEE, which no single class owns: it is
# Odoo::SourceStamp, Odoo::Attribution, Odoo::Accounting and Odoo::DestinationProfile together, against a fake
# server. Naming one of them would misdescribe what breaks when this file fails.
RSpec.describe 'Odoo project isolation inside one shared company' do
  include_context 'with commerce encryption'

  # ONE company, ONE journal, TWO projects distinguished only by their analytic account.
  let(:shared_company) { 3 }
  let(:shared_journal) { 11 }
  let(:lynomia_analytic) { 41 }
  let(:atlas_analytic) { 77 }

  # Atlas Logistics' own records, as the shared company really holds them: the same company, the same journal,
  # a customer with the SAME NAME and the SAME EMAIL as a Lynomia Chat account would have, and an invoice
  # number that collides with one of ours.
  let(:atlas_rows) do
    [
      { '_model' => 'res.partner', 'id' => 900, 'name' => 'Gulf Trading LLC', 'email' => 'finance@gulf.example',
        'ref' => 'ATLAS/live/customer/cust_1', 'company_id' => [shared_company, 'Owner Holding'], 'vat' => nil },
      { '_model' => 'account.move', 'id' => 910, 'name' => 'INV/2026/0007', 'ref' => 'ATLAS/live/invoice/al_55',
        'state' => 'posted', 'payment_state' => 'paid', 'move_type' => 'out_invoice', 'amount_total' => 4000.0,
        'amount_residual' => 0.0, 'currency_id' => [1, 'KWD'], 'date' => '2026-10-01',
        'invoice_date' => '2026-10-01', 'journal_id' => [shared_journal, 'Customer Invoices'],
        'company_id' => [shared_company, 'Owner Holding'], 'partner_id' => [900, 'Gulf Trading LLC'],
        'reversed_entry_id' => false },
      { '_model' => 'account.move.line', 'id' => 911, 'display_type' => 'product', 'name' => 'Atlas freight',
        'account_id' => [700, 'Revenue'], 'analytic_distribution' => { atlas_analytic.to_s => 100.0 },
        'balance' => -4000.0, 'move_id' => 910 }
    ]
  end

  let(:odoo) { OdooSharedCompany.new(atlas_rows.dup) }
  let(:profile) do
    create(:odoo_destination_profile, environment: 'live', company_id: shared_company, journal_id: shared_journal,
                                      analytic_account_id: lynomia_analytic)
  end
  let(:accounting) { Odoo::Accounting.new(profile, client: odoo) }
  let(:attribution) { Odoo::Attribution.new(profile) }
  let(:our_stamp) { 'LYNOMIA_CHAT/live/invoice/in_1' }

  def draft_for(reference)
    Odoo::Accounting::Draft.new(partner_id: 1, reference: reference, invoice_date: '2026-10-10', currency_id: 1,
                                lines: [{ name: 'Lynomia Chat Growth plan', quantity: 1, price_unit: 100.0 }])
  end

  describe 'identity: what counts as our record' do
    # THE CENTRAL CLAIM. Atlas's invoice is in our company, our journal and of our move type; the only thing
    # that differs is the stamp. A lookup scoped by company and journal alone -- which is what this
    # integration previously claimed was sufficient -- would return it.
    it "does not find a sibling project's invoice although company, journal and type all match" do
      found = accounting.find_moves(reference: our_stamp, move_type: 'out_invoice')

      expect(found).to be_empty
      expect(odoo.calls.last[:domain]).to include(['ref', '=', our_stamp])
    end

    it "does not find a sibling project's partner by the name or the email it shares with ours" do
      found = accounting.find_partners('LYNOMIA_CHAT/live/customer/account_1')
      sent = odoo.calls.last[:domain].flatten

      expect(found).to be_empty
      # Neither the name nor the email is ever a clause. Asserted on the payload, because a future change that
      # "helpfully" matched on email would pass every other example in this file.
      expect(sent).not_to include('email')
      expect(sent).not_to include('name')
    end

    # Structural, so a new call site cannot re-break the rule: there is no way to ASK for a scope-only search.
    it 'refuses to build an ownership lookup without a stamp' do
      stamp = Odoo::SourceStamp.new(profile)

      expect { stamp.ownership_domain(model: 'account.move', reference: nil) }.to raise_error(ArgumentError)
      expect { stamp.ownership_domain(model: 'account.move', reference: '') }.to raise_error(ArgumentError)
    end

    # A read by id is the other way a sibling's record could be adopted: a stale or mistyped `odoo_record_id`
    # on one of our own mappings.
    it "refuses a read-by-id that lands on a sibling project's move, despite the matching company and journal" do
      expect { accounting.read_move(910, reference: our_stamp) }
        .to raise_error(Odoo::Error) { |error| expect(error.reason).to eq('move_stamp_mismatch') }
    end

    it 'accepts a read-by-id of our own move' do
      ours = atlas_rows.find { |row| row['_model'] == 'account.move' }
      odoo.rows << ours.merge('id' => 950, 'ref' => our_stamp)

      expect(accounting.read_move(950, reference: our_stamp)['id']).to eq(950)
    end
  end

  describe 'attribution: whose revenue Odoo will report it as' do
    it "puts 100% on this project's analytic account on an authored line" do
      accounting.create_invoice(draft_for(our_stamp))
      line = odoo.calls.last[:values]['invoice_line_ids'].first.last

      expect(line['analytic_distribution']).to eq({ lynomia_analytic.to_s => 100.0 })
      # A STRING key and a NUMERIC value, which is what Odoo's own sanitiser requires: it divides the value,
      # so a string percentage raises server-side, and it casts the key with int(), so a non-numeric key blows
      # up at posting.
      expect(line['analytic_distribution'].keys.first).to be_a(String)
      expect(line['analytic_distribution'].values.first).to be_a(Numeric)
    end

    it 'refuses a document whose revenue line came back attributed to the sibling project' do
      verdict = attribution.verify([{ 'id' => 1, 'display_type' => 'product', 'balance' => -100.0,
                                      'analytic_distribution' => { atlas_analytic.to_s => 100.0 } }])

      expect(verdict.ok?).to be(false)
      expect(verdict.reason).to eq('attribution_foreign_analytic_account')
    end

    it 'refuses a document whose revenue line came back with no attribution at all' do
      # Odoo reads an unset JSON field back as `false`, not as {}.
      verdict = attribution.verify([{ 'id' => 1, 'display_type' => 'product', 'balance' => -100.0,
                                      'analytic_distribution' => false }])

      expect(verdict.ok?).to be(false)
      expect(verdict.reason).to eq('attribution_missing')
    end

    it 'refuses a document whose revenue line came back attributed to us only in part' do
      verdict = attribution.verify([{ 'id' => 1, 'display_type' => 'product', 'balance' => -100.0,
                                      'analytic_distribution' => { lynomia_analytic.to_s => 60.0 } }])

      expect(verdict.ok?).to be(false)
      expect(verdict.reason).to eq('attribution_partial')
    end

    # Posting a receivable line that carries a distribution creates a real account.analytic.line with the
    # OPPOSITE sign, which cancels the revenue line's attribution -- so the project's analytic total silently
    # reads zero while the invoice itself looks perfect.
    it 'refuses our attribution on the receivable line, because it would cancel the revenue line' do
      verdict = attribution.verify([
                                     { 'id' => 1, 'display_type' => 'product', 'balance' => -100.0,
                                       'analytic_distribution' => { lynomia_analytic.to_s => 100.0 } },
                                     { 'id' => 2, 'display_type' => 'payment_term', 'balance' => 100.0,
                                       'analytic_distribution' => { lynomia_analytic.to_s => 100.0 } }
                                   ])

      expect(verdict.ok?).to be(false)
      expect(verdict.reason).to eq('attribution_on_receivable_line')
    end

    # A tax line IS Odoo's own doing when the tax carries the `analytic` flag, and an externally written one
    # does not survive Odoo's tax-line matching anyway. So it is reported, not refused.
    it 'accepts an analytic tax line Odoo filled itself, and says so' do
      verdict = attribution.verify([
                                     { 'id' => 1, 'display_type' => 'product', 'balance' => -100.0,
                                       'analytic_distribution' => { lynomia_analytic.to_s => 100.0 } },
                                     { 'id' => 2, 'display_type' => 'tax', 'balance' => -5.0,
                                       'analytic_distribution' => { lynomia_analytic.to_s => 100.0 } }
                                   ])

      expect(verdict.ok?).to be(true)
      expect(verdict.note).to eq('tax_lines_carry_attribution')
    end

    # account.move has no analytic field at all; attribution is a journal-item concept, and a move-level key
    # would be silently ignored by Odoo while looking like it had worked.
    it 'never writes an analytic distribution onto the move itself' do
      accounting.create_invoice(draft_for('LYNOMIA_CHAT/live/invoice/in_2'))

      expect(odoo.calls.last[:values]).not_to have_key('analytic_distribution')
    end
  end

  describe 'what is never sent' do
    it "never writes payment_state, and never names the sibling project's analytic account" do
      accounting.create_invoice(draft_for('LYNOMIA_CHAT/live/invoice/in_3'))

      expect(odoo.payloads).not_to include('payment_state')
      expect(odoo.payloads).not_to include(atlas_analytic.to_s)
    end

    # The company context is still sent -- it decides which company a write lands in -- but it is never what
    # separates the projects.
    it 'carries the company context on every call it makes' do
      accounting.find_moves(reference: our_stamp, move_type: 'out_invoice')
      accounting.read_move_lines(910)

      expect(odoo.calls.map { |call| call[:context] })
        .to all(eq({ 'allowed_company_ids' => [shared_company] }))
    end

    # Odoo's own mandatory-analytic validation sits behind this context key and the web UI is the only caller
    # that sets it, so posting over the API without it would silently accept an invoice that breaches a
    # mandatory analytic plan.
    it 'asks Odoo to validate analytics when it posts' do
      odoo.rows << atlas_rows.find { |row| row['_model'] == 'account.move' }
                             .merge('id' => 960, 'ref' => our_stamp, 'state' => 'draft')
      accounting.post_move(960)

      post = odoo.calls.find { |call| call[:method] == 'action_post' }
      expect(post[:context]['validate_analytic']).to be(true)
    end
  end

  describe 'activation' do
    it 'cannot be enabled when the attribution probe has not passed, however complete the rest is' do
      unproven = create(:odoo_destination_profile,
                        last_capability_proof: { 'ok' => true, 'probes' => { 'draft_create' => { 'ok' => true } } })

      expect(unproven.capability_proven?).to be(false)
      expect(unproven.status).to eq(:capability_unproven)
      expect { Odoo::AdminSettings.new(unproven).enable! }.to raise_error(Odoo::AdminSettings::Error)
    end

    it 'cannot be enabled when no analytic account names this project' do
      unattributed = create(:odoo_destination_profile, analytic_account_id: nil)

      expect(unattributed.status).to eq(:attribution_incomplete)
      expect { Odoo::AdminSettings.new(unattributed).enable! }.to raise_error(Odoo::AdminSettings::Error)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
