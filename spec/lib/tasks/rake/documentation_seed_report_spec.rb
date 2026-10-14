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
  let(:media) do
    Documentation::MediaSeeder::Result.new(uploaded: 1, replaced: 0, unchanged: 3, purged: 1, unmeasured: 0,
                                           unreferenced: 2)
  end
  let(:result) do
    Documentation::ContentSeeder::Result.new(created: 2, updated: 1, unchanged: 7, adopted: 0, untracked: 0,
                                             locales: %w[en ar], divergences: [], media: media)
  end

  describe 'a clean seed' do
    it 'prints one summary line and one media line, and does not abort' do
      expect { described_class.run('articles') { result } }
        .to output("articles: 2 created, 1 updated, 7 unchanged, 0 adopted, 0 untracked (en, ar)\n  " \
                   'media: 1 attached, 0 replaced, 3 unchanged (0 without dimensions); ' \
                   "sweep: 1 purged, 2 unreferenced in the repository\n").to_stdout
    end

    # The owner's five reportable categories. Four are counters; the fifth, FAILED, is not -- the media pass
    # fails loudly on the first defect rather than tallying, so it is reported by PREFLIGHT_FAILED or by
    # APPLY_FAILED naming the pass, both covered below. This asserts the four by name so a renamed or dropped
    # counter cannot pass silently.
    it 'names attached, replaced, unchanged and purged on the media line' do
      # PAIRWISE DISTINCT counters, which is what makes this example able to fail on its own: the exact-string
      # example above would also catch a renamed counter, but neither it nor an all-distinct-from-zero assertion
      # catches two format arguments swapped while both read 0. With 1/2/3/4/5/6 a swap moves a number.
      media.replaced = 2
      media.unchanged = 3
      media.purged = 4
      media.unmeasured = 5
      media.unreferenced = 6

      expect { described_class.run('articles') { result } }
        .to output(a_string_including('media: 1 attached, 2 replaced, 3 unchanged (5 without dimensions); ' \
                                      'sweep: 4 purged, 6 unreferenced in the repository')).to_stdout
    end

    # THE SWEEP IS THE LAST THING THE MEDIA PASS DOES, so on any earlier failure its counters are unknown rather
    # than zero. `0 purged, 0 unreferenced` would read as "the sweep ran and found nothing", which is the kind of
    # true-looking zero this program keeps removing.
    it 'says the sweep did not complete rather than printing zeros for it' do
      media.purged = nil
      media.unreferenced = nil

      expect { described_class.run('articles') { result } }
        .to output(a_string_including('3 unchanged (0 without dimensions); sweep: did not complete')).to_stdout
    end

    # THE SWEEP CAN DIE PARTWAY, and then `purged` holds a partial count while `unreferenced` is still nil --
    # the shape `purge_later` failing to reach the queue produces. Gating the sentence on `purged` fed nil into
    # a `%d` and the REPORT ITSELF raised TypeError, so an operator met a bare backtrace instead of the
    # APPLY FAILED block. The sentence is gated on the counter written last.
    it 'does not crash when the sweep raised after purging some of them' do
      media.purged = 2
      media.unreferenced = nil

      expect { described_class.run('articles') { result } }
        .to output(a_string_including('sweep: did not complete')).to_stdout
    end

    # A Result built by hand carries no media pass. A live run that refuses BEFORE the media preflight is reached
    # leaves it nil too, but that path aborts through PREFLIGHT_FAILED without printing a summary -- so this
    # branch is reached only by a hand-built Result, and the line is absent rather than printed as zeros.
    it 'prints no media line when the media pass did not run' do
      result.media = nil

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
                                                         untracked: 0, locales: ['en'], divergences: [],
                                                         media: media)
      )
    end

    it 'prints the counts of everything that completed before aborting' do
      expect do
        expect { expect { described_class.run('articles') { raise failure } }.to raise_error(SystemExit) }
          .to output(/articles: 4 created/).to_stdout
      end.to output(/APPLY FAILED/).to_stderr
    end

    # The media counts are part of "what completed". `ContentSeeder#apply!` assigns the LIVE MediaSeeder::Result
    # before the pass runs, so an attach that fails on the tenth key still reports the nine that landed -- and a
    # failure in the media pass itself names it, so an operator knows which half to look at.
    it 'prints the media counts too, and can name the media pass as the failure site' do
      media_failure = Documentation::ContentSeeder::ApplyFailure.new(
        where: 'the corpus media pass', result: failure.result,
        cause: Documentation::MediaSeeder::Error.new('media:a/b.png: image/svg+xml is not permitted')
      )

      expect do
        expect { expect { described_class.run('articles') { raise media_failure } }.to raise_error(SystemExit) }
          .to output(/media: 1 attached, 0 replaced, 3 unchanged/).to_stdout
      end.to output(/APPLY FAILED at the corpus media pass: Documentation::MediaSeeder::Error/).to_stderr
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
