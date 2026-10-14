# Lynomia global documentation: one-time setup and content seeding, run by an operator rather than by a web request.
#
# The report both seeding tasks print is here rather than in the seeder because the seeder returns data and a rake
# task is where an operator reads it. It touches NO application constant on purpose: a .rake file is loaded by
# `Rails.application.load_tasks`, which runs before the application is initialized, so an autoloadable constant does
# not resolve at this point (measured: `Rails.application.initialized?` is false and the constant is undefined).
module DocumentationSeedReport
  SUMMARY = '%<label>s: %<created>d created, %<updated>d updated, %<unchanged>d unchanged, ' \
            '%<adopted>d adopted, %<untracked>d untracked (%<locales>s)'.freeze

  # A row the corpus cannot write is the one thing an operator has to act on, so the task exits non-zero for it.
  # `operator_edited` is a state an operator may legitimately be living in: it prints and the task still succeeds,
  # because a red exit on a routine run trains people to ignore the exit code.
  ADOPT_INSTRUCTIONS = <<~TEXT.freeze
    Those rows carry no seeder provenance, so there is no way to tell a previous seed's own writing from an
    operator's edit and nothing was written to them. Check that none of them holds an edit worth keeping, then
    run once with ADOPT_UNTRACKED=1 to apply the corpus to them and record what it wrote.
  TEXT

  def self.print(result, label)
    puts format(SUMMARY, label: label, created: result.created, updated: result.updated,
                         unchanged: result.unchanged, adopted: result.adopted, untracked: result.untracked,
                         locales: result.locales.join(', '))
    result.divergences.each { |divergence| puts "  #{line(divergence)}" }
    abort(ADOPT_INSTRUCTIONS) if result.untracked.positive?
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
    result = Documentation::ContentSeeder.changelog(adopt_untracked: ENV['ADOPT_UNTRACKED'] == '1').perform!
    DocumentationSeedReport.print(result, 'releases')
  end

  desc 'Seed the Lynomia documentation corpus from custom/db/documentation'
  task content: :environment do
    result = Documentation::ContentSeeder.new(adopt_untracked: ENV['ADOPT_UNTRACKED'] == '1').perform!
    DocumentationSeedReport.print(result, 'articles')
  end
end
