# Lynomia global documentation: one-time setup and content seeding, run by an operator rather than by a web request.
#
# The report both seeding tasks print is here rather than in the seeder because the seeder returns data and a rake
# task is where an operator reads it. It touches NO application constant at load time on purpose: a .rake file is
# loaded by `Rails.application.load_tasks`, which runs before the application is initialized, so an autoloadable
# constant does not resolve at this point (measured: `Rails.application.initialized?` is false and the constant is
# undefined). Every constant below is therefore named inside a method body, which runs under `:environment`.
module DocumentationSeedReport
  SUMMARY = '%<label>s: %<created>d created, %<updated>d updated, %<unchanged>d unchanged, ' \
            '%<adopted>d adopted, %<untracked>d untracked (%<locales>s)'.freeze

  # THE CORPUS MEDIA LINE, indented under the summary the way a divergence is. The wording is
  # R2-MEDIA-INTERFACE.md section 3.7's own suggested line, which is also the owner's report vocabulary:
  # `uploaded` prints as "attached", because an attachment is the thing that exists afterwards.
  #
  # FAILED is deliberately not a count. The media pass fails loudly on the first defect rather than tallying
  # defects, so a failure is reported by PREFLIGHT_FAILED (a corpus defect, nothing written) or by APPLY_FAILED
  # naming `the corpus media pass` (a write that failed, with these counts above it) -- never by a zero here.
  MEDIA = '  media: %<uploaded>d attached, %<replaced>d replaced, %<unchanged>d unchanged ' \
          '(%<unmeasured>d without dimensions)'.freeze

  # The orphan sweep is the LAST thing the media pass does, so on any earlier failure its two counters are not
  # zero -- they are unknown. Printing `0 purged, 0 unreferenced` there would claim the sweep ran and found
  # nothing, which is the kind of true-looking zero this program keeps removing. `nil` prints as the sentence
  # instead, and a run that reached the sweep prints the counts.
  SWEEP = '; sweep: %<purged>d purged, %<unreferenced>d unreferenced in the repository'.freeze
  UNSWEPT = '; sweep: did not run'.freeze

  # A row the corpus cannot write is the one thing an operator has to act on, so the task exits non-zero for it.
  # `operator_edited` is a state an operator may legitimately be living in: it prints and the task still succeeds,
  # because a red exit on a routine run trains people to ignore the exit code.
  ADOPT_INSTRUCTIONS = <<~TEXT.freeze
    Those rows carry no seeder provenance, so there is no way to tell a previous seed's own writing from an
    operator's edit and nothing was written to them. Check that none of them holds an edit worth keeping, then
    run once with ADOPT_UNTRACKED=1 to apply the corpus to them and record what it wrote.
  TEXT

  # The preflight refused: the corpus is not applicable, and the database is exactly as the run found it. The whole
  # list is printed because an operator fixing a corpus wants every file at once.
  PREFLIGHT_FAILED = <<~TEXT.freeze
    %<label>s: the corpus will not apply cleanly, so NOTHING was written. Every file to fix:
    %<problems>s
  TEXT

  # A write failed after the preflight passed. There is no transaction to roll back -- deliberately, because media
  # attachments and their files are outside any database transaction (owner ruling 3) -- so what an operator needs
  # instead is exactly this: what completed, what failed, and that a re-run is safe.
  APPLY_FAILED = <<~TEXT.freeze
    %<label>s: APPLY FAILED at %<message>s
    The counts above are everything that completed, and they are committed: nothing was rolled back and no file
    after this one was applied. Fix the cause and run the task again -- every write is an upsert, on
    (slug, locale) for an article and on the `media:` key for an attachment, so a re-run reapplies what
    completed as `unchanged` and carries on from the file that failed.
  TEXT

  # Both seed tasks run through here, so both report the same way in all three outcomes.
  def self.run(label)
    print(yield, label)
  rescue Documentation::ContentSeeder::PreflightError => e
    abort(format(PREFLIGHT_FAILED, label: label, problems: e.message))
  rescue Documentation::ContentSeeder::ApplyFailure => e
    summary(e.result, label)
    abort(format(APPLY_FAILED, label: label, message: e.message))
  end

  def self.print(result, label)
    summary(result, label)
    abort(ADOPT_INSTRUCTIONS) if result.untracked.positive?
  end

  def self.summary(result, label)
    puts format(SUMMARY, label: label, created: result.created, updated: result.updated,
                         unchanged: result.unchanged, adopted: result.adopted, untracked: result.untracked,
                         locales: result.locales.join(', '))
    # A live run CAN produce a nil `media` -- a refusal before the media preflight is reached leaves it unset --
    # but that path aborts through PREFLIGHT_FAILED without printing a summary, so this guard is reached only by
    # a Result built by hand. Kept, and said plainly, rather than left as something a later reader might take as
    # evidence that a live summary can be media-less.
    puts media_line(result.media) if result.media
    result.divergences.each { |divergence| puts "  #{line(divergence)}" }
  end

  def self.media_line(media)
    sweep = media.purged.nil? ? UNSWEPT : format(SWEEP, purged: media.purged, unreferenced: media.unreferenced)
    format(MEDIA, **media.to_h) + sweep
  end

  def self.line(divergence)
    [divergence.kind, divergence.locale, divergence.slug, divergence.path,
     divergence.fields.join(', ')].reject(&:blank?).join('  ')
  end
end

namespace :documentation do
  desc 'Create or update the Lynomia documentation and changelog portals'
  task setup: :environment do
    Documentation::PortalSeeder.new.perform!.each do |portal|
      puts "#{portal.slug}: #{portal.name} (#{portal.config['allowed_locales'].join(', ')})"
    end
  end

  desc 'Seed the Lynomia changelog from custom/db/changelog'
  task changelog: :environment do
    # `== '1'` and not `.present?`: every non-empty value was truthy, so `ADOPT_UNTRACKED=0` -- which an operator
    # types to mean OFF -- silently applied the corpus over untracked rows. `1` is the value the instructions
    # already name, so accepting only it IS the documented interface and every off-looking value is off.
    DocumentationSeedReport.run('releases') do
      Documentation::ContentSeeder.changelog(adopt_untracked: ENV['ADOPT_UNTRACKED'] == '1').perform!
    end
  end

  desc 'Seed the Lynomia documentation corpus from custom/db/documentation'
  task content: :environment do
    DocumentationSeedReport.run('articles') do
      Documentation::ContentSeeder.new(adopt_untracked: ENV['ADOPT_UNTRACKED'] == '1').perform!
    end
  end
end
