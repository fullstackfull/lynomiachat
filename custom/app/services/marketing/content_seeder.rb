# Writes the website the repository ships into the database, once, and never again over an operator's work.
#
# THE IDEMPOTENCY RULE IS THE WHOLE DESIGN, and it is copied from `ConfigLoader` because that pattern is
# already load-bearing in this application: it runs on every `db:migrate`
# (lib/tasks/db_enhancements.rake:2-7) with `reconcile_only_new: true` (lib/config_loader.rb:3,50-52) and
# NEVER overwrites a row that exists. Same here. A missing page is created; a page an operator has edited is
# left exactly as it is, including one they deliberately emptied.
#
# WHY IT RUNS ON DEPLOY RATHER THAN BY HAND. The public controllers read `site_pages` and nothing else -- so
# a page with no row is a 404, and the 96 URLs the site ships have to exist before the first request. A seed
# an operator must remember to run is a seed that gets skipped; hooking the same rake task the installation
# config already uses means the rows arrive with the migration that creates the table.
#
# WHAT `--force` DOES AND WHY IT IS NOT THE DEFAULT. `reconcile_only_new: false` rewrites every page from the
# repository, discarding operator edits. It exists because the alternative -- an operator who has broken a
# page with no way back -- is worse, and because the W6 runbook needs a documented way to restore the shipped
# content. It is never what a deploy does.
module Marketing::ContentSeeder
  # What the seeder did, so a caller can print it and a spec can assert on it.
  Report = Struct.new(:created, :updated, :skipped, :errors, keyword_init: true) do
    def to_s
      "created #{created}, updated #{updated}, left alone #{skipped}" +
        (errors.any? ? ", #{errors.size} refused" : '')
    end

    def ok? = errors.empty?
  end

  class << self
    def apply!(locales: MarketingHelper::LOCALES, reconcile_only_new: true)
      report = Report.new(created: 0, updated: 0, skipped: 0, errors: [])

      locales.each do |locale|
        seed_pages(locale, report, reconcile_only_new)
        seed_nav_links(locale, report, reconcile_only_new)
        seed_faq_entries(locale, report, reconcile_only_new)
      end

      report
    end

    # Every page the site is supposed to serve, as [locale, kind, key]. The seeder's own contract, and what
    # the W6 coverage spec asserts the route table against.
    def expected_pages
      MarketingHelper::LOCALES.flat_map do |locale|
        Marketing::ContentBlueprint.pages(locale).map { |page| [locale, page[:kind], page[:key]] }
      end
    end

    private

    def seed_pages(locale, report, only_new)
      Marketing::ContentBlueprint.pages(locale).each do |attributes|
        page = SitePage.find_or_initialize_by(locale: locale, kind: attributes[:kind], key: attributes[:key])
        next record_skip(report) if page.persisted? && only_new

        # A seeded page is published: it is content that has been reviewed in a pull request, and a site whose
        # pages all arrive as drafts is a site that serves 96 blank 404s until somebody clicks 96 times.
        page.assign_attributes(attributes.merge(status: :published))
        save(page, report, "#{locale}/#{attributes[:kind]}/#{attributes[:key]}")
      end
    end

    # Navigation and FAQ rows have no natural key an operator would recognise, so "already seeded" is answered
    # per locale and placement rather than per row: if the operator has any header links, their header is
    # theirs. Re-seeding row by row would reinstate a link they deleted on every deploy.
    def seed_nav_links(locale, report, only_new)
      Marketing::ContentBlueprint.nav_links(locale).group_by { |link| link[:placement] }.each do |placement, links|
        placed = SiteNavLink.for_locale(locale).where(placement: placement)
        next record_skip(report, links.size) if only_new && placed.exists?

        placed.destroy_all unless only_new
        links.each do |attributes|
          link = SiteNavLink.new(attributes.merge(locale: locale))
          save(link, report, "#{locale}/nav/#{placement}/#{attributes[:label]}")
        end
      end
    end

    def seed_faq_entries(locale, report, only_new)
      entries = Marketing::ContentBlueprint.faq_entries(locale)
      return record_skip(report, entries.size) if only_new && SiteFaqEntry.for_locale(locale).exists?

      SiteFaqEntry.for_locale(locale).destroy_all unless only_new
      entries.each do |attributes|
        entry = SiteFaqEntry.new(attributes.merge(locale: locale))
        save(entry, report, "#{locale}/faq/#{attributes[:question].to_s.truncate(40)}")
      end
    end

    # A refusal is collected rather than raised: one bad page should not stop the other 95 from arriving, and
    # the caller prints what was refused. `documentation:content` exits non-zero on a problem for the same
    # reason, and the rake task here does too.
    def save(record, report, label)
      was_new = record.new_record?
      if record.save
        was_new ? report.created += 1 : report.updated += 1
      else
        report.errors << "#{label}: #{record.errors.full_messages.join(', ')}"
      end
    end

    def record_skip(report, count = 1)
      report.skipped += count
    end
  end
end
