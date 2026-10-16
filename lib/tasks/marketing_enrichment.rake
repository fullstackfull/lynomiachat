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

# The order outcomes are printed in: what was done first, what needs attention last. A status this list does
# not know sorts to the end rather than being dropped, so a new one cannot go unseen.
MARKETING_ENRICH_ORDER = %i[added would_add present invalid refused image_missing missing_page].freeze

# The statuses that make a run a failure. A plan that cannot apply cleanly should fail a pipeline that runs
# it as a check, which is what the non-zero exit is for.
MARKETING_ENRICH_PROBLEMS = %i[invalid refused image_missing missing_page].freeze

def print_enrichment_report(outcomes, verb)
  outcomes
    .sort_by { |outcome| [MARKETING_ENRICH_ORDER.index(outcome.status) || MARKETING_ENRICH_ORDER.size, outcome.key] }
    .each do |o|
      puts format('  %<status>-14s %<locale>s/%<slug>-18s %<key>-28s %<detail>s',
                  status: o.status, locale: o.locale, slug: o.slug, key: o.key, detail: o.detail)
    end

  problems = outcomes.count { |outcome| MARKETING_ENRICH_PROBLEMS.include?(outcome.status) }
  puts "\n#{verb}: #{outcomes.size} declared, #{problems} with a problem"
  problems
end

namespace :marketing do
  namespace :enrich do
    desc 'Show what marketing:enrich would add to existing pages. Writes nothing.'
    task plan: :environment do
      outcomes = Marketing::PageEnrichment.plan(only: ENV['ONLY'].presence&.split(',')&.map(&:strip))
      exit(1) if print_enrichment_report(outcomes, 'planned').positive?
    end
  end

  desc 'Add approved sections and screenshots to existing marketing pages. Idempotent; never overwrites.'
  task enrich: :environment do
    outcomes = Marketing::PageEnrichment.apply!(only: ENV['ONLY'].presence&.split(',')&.map(&:strip))
    exit(1) if print_enrichment_report(outcomes, 'applied').positive?
  end
end
