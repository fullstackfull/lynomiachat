require 'rake'
require 'rails_helper'

# The operator's answer to "why does /pricing not show my plan?", printed from the server.
#
# THE CASE THAT USED TO CRASH IS THE ORDINARY ONE. The task ended with `return if published.any?`, and a
# Rake task's body is a block, not a method -- so on any server that HAD a published plan, the task printed
# its whole report and then died with LocalJumpError on the last line. The failure was invisible on a server
# with nothing published, which is exactly the server an operator reaches for this task on, so the healthy
# case was the broken one. Each of the three states is asserted to run to completion below.
RSpec.describe Rake::Task do
  describe 'pricing:diagnose' do
    subject(:task) { described_class['pricing:diagnose'] }

    before { task.reenable }

    # Rake tasks are loaded once per process; without this the suite's first `invoke` would be the only one.
    def run
      output = nil
      expect { output = capture_task_output }.not_to raise_error
      output
    end

    def capture_task_output
      captured = StringIO.new
      original = $stdout
      $stdout = captured
      task.invoke
      captured.string
    ensure
      $stdout = original
    end

    context 'when there are no plans at all' do
      it 'reports the empty installation and does not raise' do
        output = run

        expect(output).to include('billing plans on this server: 0')
        expect(output).to include('There are no BillingPlan rows at all')
      end
    end

    context 'when plans exist but none is published' do
      before do
        create(:billing_plan, name: 'Inactive One', active: false, listed_on_website: true)
        create(:billing_plan, name: 'Unlisted One', active: true, listed_on_website: false)
      end

      it 'names each plan and the reason it is withheld, and does not raise' do
        output = run

        expect(output).to include('the pricing page would publish: 0')
        expect(output).to match(/Inactive One.*withheld: not active/)
        expect(output).to match(/Unlisted One.*withheld: not ticked "Listed on website"/)
        expect(output).to include('No plan is published, so the pricing page shows its quote form')
      end

      # A withheld plan may be a negotiated rate; its price is not for terminal scrollback.
      it 'does not print the price of a plan it is withholding' do
        output = run

        expect(output).to include('(not shown)')
        expect(output).not_to include('USD 10.00')
      end
    end

    # The regression. Before the fix this raised LocalJumpError after printing the report.
    context 'when at least one plan is published' do
      before { create(:billing_plan, name: 'Growth', active: true, listed_on_website: true) }

      it 'runs to completion and reports the published plan' do
        output = run

        expect(output).to include('the pricing page would publish: 1')
        expect(output).to match(%r{Growth.*PUBLISHED.*USD 10\.00 / month})
      end

      # The closing paragraph belongs to the nothing-published case only. It was what the broken `return`
      # was trying to skip, so it is asserted absent as well as present above.
      it 'omits the nothing-published note' do
        expect(run).not_to include('No plan is published')
      end
    end

    context 'when published and withheld plans are mixed' do
      before do
        create(:billing_plan, name: 'Growth', active: true, listed_on_website: true)
        create(:billing_plan, name: 'Internal', active: true, listed_on_website: false)
      end

      it 'reports both, prices only the published one, and does not raise' do
        output = run

        expect(output).to include('billing plans on this server: 2')
        expect(output).to include('the pricing page would publish: 1')
        expect(output).to match(/Growth.*PUBLISHED/)
        expect(output).to match(/Internal.*withheld.*\(not shown\)/)
        expect(output).not_to include('No plan is published')
      end
    end

    # Read-only is the whole premise: an operator runs this on production.
    it 'writes nothing' do
      create(:billing_plan, name: 'Growth', active: true, listed_on_website: true)
      create(:billing_plan, name: 'Internal', active: true, listed_on_website: false)

      expect { run }.not_to(change { [BillingPlan.count, BillingPlan.order(:id).pluck(:active, :listed_on_website)] })
    end
  end
end
