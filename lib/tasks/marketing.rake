# The official website's content seed and its verification, run by an operator rather than by a web request.
#
# IT TOUCHES NO APPLICATION CONSTANT AT LOAD TIME. A .rake file is loaded by
# `Rails.application.load_tasks`, which runs before the application is initialized, so an autoloadable
# constant does not resolve at this point -- the same constraint lib/tasks/documentation.rake records at its
# head. Every constant below is named inside a task body, which runs under `:environment`.
#
# WHY THIS IS NOT HOOKED TO `db:migrate` the way ConfigLoader is (lib/tasks/db_enhancements.rake:2-7). Two
# reasons, and the second is the decisive one:
#
#   1. It follows the documentation precedent. `documentation:content` is operator-run because content is
#      reviewed, not incidental, and an operator wants to read the report.
#   2. A hook would make the test database depend on HOW it was built. `maintain_test_schema!`
#      (spec/rails_helper.rb:40) loads `db/schema.rb` rather than running migrations when the schema is
#      stale, so the hook would fire on a migrated database and not on a loaded one -- and specs would pass
#      or fail according to which happened. Specs seed inside their own transaction instead.
#
# SO THE DEPLOY RUNS IT EXPLICITLY, and `marketing:verify` is how the deploy proves it worked: the public
# controllers read `site_pages` and nothing else, so a page with no row is a 404, and that must fail a deploy
# rather than greet a visitor.
namespace :marketing do
  desc 'Seed the official website content (additive: never overwrites a row an operator has edited)'
  task content: :environment do
    report = Marketing::ContentSeeder.apply!
    puts "[marketing:content] #{report}"
    report.errors.each { |error| warn "[marketing:content] REFUSED #{error}" }
    abort('[marketing:content] some content could not be written; the pages it covers will 404') unless report.ok?
  end

  desc 'Restore the repository content over the live rows, DISCARDING operator edits'
  task 'content:restore': :environment do
    report = Marketing::ContentSeeder.apply!(reconcile_only_new: false)
    puts "[marketing:content:restore] #{report}"
    report.errors.each { |error| warn "[marketing:content:restore] REFUSED #{error}" }
    abort('[marketing:content:restore] some content could not be written') unless report.ok?
  end

  # The deploy's proof. Every page the route table can reach has a published row in both locales, or this
  # exits non-zero and names what is missing.
  desc 'Verify every website URL has a published page row (exits non-zero if any is missing)'
  task verify: :environment do
    missing = Marketing::ContentSeeder.expected_pages.reject do |locale, kind, key|
      SitePage.live.exists?(locale: locale, kind: kind, key: key)
    end

    if missing.empty?
      puts "[marketing:verify] all #{Marketing::ContentSeeder.expected_pages.size} pages are published"
    else
      missing.each { |locale, kind, key| warn "[marketing:verify] MISSING #{locale} #{kind}/#{key}" }
      abort("[marketing:verify] #{missing.size} page(s) have no published row and would 404")
    end
  end
end
