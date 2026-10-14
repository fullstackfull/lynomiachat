require 'rake'
require 'rails_helper'

# THE OPERATOR'S VIEW OF OWNER RULING 3. The seeder decides everything before it writes and then writes
# idempotently; this module is the half an operator actually reads, and the ruling's requirement C -- "report
# exactly what completed and what failed, leave the task safely rerunnable, do not silently continue" -- is a
# property of this reporting rather than of the seeder.
#
# All four outcomes are covered because they differ in EXIT CODE as well as in text, and the runbook keys off
# the exit code: a refused preflight and a failed apply are both non-zero, a clean run holding untracked rows is
# non-zero too, and only a clean run without them is zero. `abort` writes its message to stderr and raises
# SystemExit, so an aborting example asserts on both streams -- which is also what keeps the suite's own output
# clean.
#
# `rails_helper` has already called `Rails.application.load_tasks` (spec/rails_helper.rb:12), which is what
# defines this module: it is declared in lib/tasks/documentation.rake, not under an autoload path.
RSpec.describe DocumentationSeedReport do
  let(:result) do
    Documentation::ContentSeeder::Result.new(created: 2, updated: 1, unchanged: 7, adopted: 0, untracked: 0,
                                             locales: %w[en ar], divergences: [])
  end

  describe 'a clean seed' do
    it 'prints one summary line and does not abort' do
      expect { described_class.run('articles') { result } }
        .to output("articles: 2 created, 1 updated, 7 unchanged, 0 adopted, 0 untracked (en, ar)\n").to_stdout
    end

    it 'prints one indented line per reported divergence' do
      result.divergences = [
        Documentation::ContentSeeder::Divergence.new(kind: 'operator_edited', locale: 'en', slug: 'audit-logs',
                                                     path: 'en/audit-logs.md',
                                                     fields: ['title', 'meta.description'])
      ]

      expect { described_class.run('articles') { result } }
        .to output(%r{\n  operator_edited  en  audit-logs  en/audit-logs\.md  title, meta\.description\n})
        .to_stdout
    end
  end

  # An untracked row is the one state the corpus cannot resolve on its own, so the run is deliberately red even
  # though no write failed: the red exit is what carries ADOPT_UNTRACKED to the operator.
  describe 'a seed that found untracked rows' do
    before { result.untracked = 3 }

    it 'prints the counts, then aborts with the adoption instructions' do
      expect do
        expect { expect { described_class.run('articles') { result } }.to raise_error(SystemExit) }
          .to output(/3 untracked/).to_stdout
      end.to output(/run once with ADOPT_UNTRACKED=1/).to_stderr
    end
  end

  # NOTHING WAS WRITTEN, and the message has to say so, because the operator's next action differs: there is no
  # partial state to reconcile. The whole problem list is printed so a corpus is fixed in one pass.
  describe 'a seed the preflight refused' do
    let(:failure) do
      Documentation::ContentSeeder::PreflightError.new(
        "en/audit-logs.md: no `title`\nar/billing.md: no English sibling"
      )
    end

    it 'aborts saying nothing was written, and lists every offending file' do
      expect { expect { described_class.run('articles') { raise failure } }.to raise_error(SystemExit) }
        .to output(%r{NOTHING was written.*en/audit-logs\.md: no `title`.*ar/billing\.md: no English sibling}m)
        .to_stderr
    end

    it 'prints no summary, because no counts exist to report' do
      expect do
        expect { expect { described_class.run('articles') { raise failure } }.to raise_error(SystemExit) }
          .not_to output(/created/).to_stdout
      end.to output(/NOTHING was written/).to_stderr
    end
  end

  # REQUIREMENT C ITSELF. There is no transaction to roll back -- an attachment and its file are outside one --
  # so what replaces atomicity is the count of what completed plus the statement that a re-run is safe.
  describe 'a seed whose apply failed after the preflight passed' do
    let(:failure) do
      Documentation::ContentSeeder::ApplyFailure.new(
        where: 'en/billing.md',
        cause: ActiveRecord::RecordNotUnique.new('duplicate key value violates unique constraint'),
        result: Documentation::ContentSeeder::Result.new(created: 4, updated: 0, unchanged: 0, adopted: 0,
                                                         untracked: 0, locales: ['en'], divergences: [])
      )
    end

    it 'prints the counts of everything that completed before aborting' do
      expect do
        expect { expect { described_class.run('articles') { raise failure } }.to raise_error(SystemExit) }
          .to output(/articles: 4 created/).to_stdout
      end.to output(/APPLY FAILED/).to_stderr
    end

    # One example for the whole message: where it failed, the underlying cause so the operator is not left
    # guessing, that what completed is committed, and that the task is safe to run again.
    it 'names the file, the cause, that the completed rows are committed, and that a re-run is safe' do
      message = a_string_including('APPLY FAILED at en/billing.md: ActiveRecord::RecordNotUnique: duplicate key')
                .and(a_string_including('nothing was rolled back'))
                .and(a_string_including('run the task again'))

      expect do
        expect { expect { described_class.run('articles') { raise failure } }.to raise_error(SystemExit) }
          .to output(message).to_stderr
      end.to output(/articles: 4 created/).to_stdout
    end
  end
end
