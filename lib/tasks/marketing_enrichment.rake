# Applying approved marketing content to pages that already exist.
#
# TWO TASKS, AND THE READ-ONLY ONE IS THE DEFAULT HABIT. `marketing:enrich:plan` writes nothing and prints
# exactly what `marketing:enrich` would do. Run it first, on production, and read it -- the apply step is a
# publishing decision on a live site, and the mechanism deliberately has no deploy hook to make it for you.
#
#   bundle exec rails marketing:enrich:plan
#   bundle exec rails marketing:enrich:plan ONLY=home.flow.en,home.flow.ar
#   bundle exec rails marketing:enrich
#
# `ONLY` narrows both tasks to named keys, which is also how an operator permanently declines one: leave it
# out of the list they run.
namespace :marketing do
  STATUS_ORDER = %i[added would_add present invalid refused image_missing missing_page].freeze

  def print_enrichment_report(outcomes, verb)
    by_status = outcomes.group_by(&:status)

    STATUS_ORDER.each do |status|
      rows = by_status[status]
      next if rows.blank?

      puts "#{status} (#{rows.size}):"
      rows.each { |row| puts "  #{row.locale}/#{row.slug}  #{row.key}  -- #{row.detail}" }
    end

    unknown = by_status.keys - STATUS_ORDER
    unknown.each { |status| by_status[status].each { |row| puts "#{status}: #{row.key} -- #{row.detail}" } }

    problems = outcomes.count { |o| %i[invalid refused image_missing missing_page].include?(o.status) }
    puts "\n#{verb}: #{outcomes.size} declared, #{problems} with a problem"
    problems
  end

  namespace :enrich do
    desc 'Show what marketing:enrich would add to existing pages. Writes nothing.'
    task plan: :environment do
      only = ENV['ONLY'].presence&.split(',')&.map(&:strip)
      outcomes = Marketing::PageEnrichment.plan(only: only)
      problems = print_enrichment_report(outcomes, 'planned')
      # A plan that cannot be applied cleanly should fail a pipeline that runs it as a check.
      exit(1) if problems.positive?
    end
  end

  desc 'Add approved sections and screenshots to existing marketing pages. Idempotent; never overwrites.'
  task enrich: :environment do
    only = ENV['ONLY'].presence&.split(',')&.map(&:strip)
    outcomes = Marketing::PageEnrichment.apply!(only: only)
    problems = print_enrichment_report(outcomes, 'applied')
    exit(1) if problems.positive?
  end
end
