require 'rails_helper'

# Whose revenue a journal item is, inside one shared Odoo company
# (custom/app/services/odoo/attribution.rb).
#
# The project-isolation behaviour against a realistic shared company is in
# spec/security/odoo_project_isolation_spec.rb. These examples are about the VALUE this class produces and the
# shapes of Odoo data it has to survive -- the gotchas that come out of Odoo's own source rather than from a
# general idea of how a JSON field behaves.
RSpec.describe Odoo::Attribution do
  subject(:attribution) { described_class.new(profile) }

  include_context 'with commerce encryption'

  let(:profile) { create(:odoo_destination_profile, analytic_account_id: 41) }

  def product_line(distribution, id: 1, account: 700)
    { 'id' => id, 'display_type' => 'product', 'balance' => -100.0, 'account_id' => [account, 'Revenue'],
      'analytic_distribution' => distribution }
  end

  describe 'the value written onto a revenue line' do
    it 'is a string key and a numeric percentage, which is what Odoo requires' do
      # Odoo's own sanitiser divides the value, so a string percentage raises server-side, and it casts the
      # key with int(), so a non-numeric key blows up at posting.
      expect(attribution.line_values).to eq({ 'analytic_distribution' => { '41' => 100.0 } })
    end

    it 'is empty when nothing is configured, so an unconfigured destination cannot write a half-attribution' do
      profile.analytic_account_id = nil

      expect(attribution.configured?).to be(false)
      expect(attribution.line_values).to eq({})
    end

    context 'with the dedicated income account fallback' do
      let(:profile) { create(:odoo_destination_profile, :income_account_attribution) }

      it 'sets the account instead of a distribution, and never both' do
        expect(attribution.line_values).to eq({ 'account_id' => 700 })
        expect(attribution.mode).to eq(described_class::INCOME_ACCOUNT)
      end
    end
  end

  describe 'what is recorded on the document mapping' do
    # The profile is mutable. A mapping that stored only "see the profile" would silently rewrite its own
    # history the moment an operator chose a different analytic account.
    it 'names the mechanism and the account this document was actually attributed to' do
      expect(attribution.mapping_values).to eq({ attribution_mode: 'analytic', odoo_analytic_account_id: 41,
                                                 odoo_income_account_id: nil })
    end

    context 'with the dedicated income account fallback' do
      let(:profile) { create(:odoo_destination_profile, :income_account_attribution) }

      it 'names the income account and leaves the analytic column empty' do
        expect(attribution.mapping_values).to eq({ attribution_mode: 'income_account',
                                                   odoo_analytic_account_id: nil, odoo_income_account_id: 700 })
      end
    end
  end

  describe 'reading Odoo back' do
    it 'treats false as unset, because that is how Odoo returns an empty JSON column' do
      expect(attribution.verify([product_line(false)]).reason).to eq('attribution_missing')
    end

    it 'treats an empty hash as unset too' do
      expect(attribution.verify([product_line({})]).reason).to eq('attribution_missing')
    end

    # From Odoo 17 a key may be a comma-joined list of ids, meaning one allocation charged to one account per
    # analytic plan. Our account inside such a key still attributes the line to us.
    it 'accepts our account inside a multi-plan key' do
      expect(attribution.verify([product_line({ '41,88' => 100.0 })]).ok?).to be(true)
    end

    # THE DISTINCTION A FLAT ID LIST WOULD LOSE. "41,88" is ONE allocation charged to one account per plan --
    # the same money, tracked twice -- while two separate entries are the line being SPLIT, and the half that
    # does not name this project is our revenue credited elsewhere.
    it 'refuses a separate allocation to another account, which is a real split of our revenue' do
      verdict = attribution.verify([product_line({ '41' => 60.0, '88' => 40.0 })])

      expect(verdict.ok?).to be(false)
      expect(verdict.reason).to eq('attribution_foreign_analytic_account')
    end

    it 'accepts a percentage that came back rounded, since Odoo rounds to analytic_precision' do
      expect(attribution.verify([product_line({ '41' => 99.995 })]).ok?).to be(true)
      expect(attribution.verify([product_line({ '41' => 99.0 })]).ok?).to be(false)
    end

    it 'accepts a percentage Odoo returned as a string rather than a number' do
      expect(attribution.verify([product_line({ '41' => '100' })]).ok?).to be(true)
    end

    it 'refuses to call an empty read a pass' do
      # A read that returned nothing is not evidence of attribution; it is evidence of nothing.
      expect(attribution.verify([]).reason).to eq('attribution_no_lines_read')
      expect(attribution.verify(nil).reason).to eq('attribution_no_lines_read')
    end

    it 'refuses a move with no revenue line at all' do
      note = { 'id' => 9, 'display_type' => 'line_note', 'balance' => 0.0, 'analytic_distribution' => false }

      expect(attribution.verify([note]).reason).to eq('attribution_no_revenue_line')
    end

    it 'requires EVERY revenue line to carry it, not just the first' do
      lines = [product_line({ '41' => 100.0 }, id: 1), product_line(false, id: 2)]

      verdict = attribution.verify(lines)
      expect(verdict.ok?).to be(false)
      expect(verdict.detail).to eq('line_2')
    end
  end

  describe 'the income account mode read back' do
    let(:profile) { create(:odoo_destination_profile, :income_account_attribution) }

    it 'passes when every revenue line uses the configured income account' do
      expect(attribution.verify([product_line(false, account: 700)]).ok?).to be(true)
    end

    it 'fails when a revenue line landed on a different account' do
      verdict = attribution.verify([product_line(false, account: 999)])

      expect(verdict.ok?).to be(false)
      expect(verdict.reason).to eq('attribution_income_account_not_applied')
    end
  end

  describe 'what it never puts in a detail' do
    # A verification failure is reported on the Invoices screen and in an operations signal, so its detail
    # has to be enough to find the line in Odoo and nothing else.
    it 'identifies the line by id only, never by its description' do
      verdict = attribution.verify([product_line(false, id: 5001).merge('name' => 'Acme Corp Growth plan')])

      expect(verdict.detail).to eq('line_5001')
      expect(verdict.to_h.to_s).not_to include('Acme')
    end
  end
end
