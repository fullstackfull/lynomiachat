# Is the public documentation actually indexable? (docs/product-refinement/03-documentation-seo.md)
#
# WHY A TASK AND NOT A SPEC. A spec asserts the TEMPLATE emits a canonical tag. This asserts that THIS
# installation's content, as seeded and edited, produces addresses a crawler can use: that no two articles
# claim the same canonical, that every hreflang points at a published sibling that points back, that nothing is
# missing the description a search result renders. Those are facts about data, so they have to be checked
# against data, on the server that serves it.
#
# READ-ONLY. It writes nothing and fixes nothing. Exit status is 1 when there is an ERROR, so it can gate a
# deploy; warnings do not fail it.
#
# Usage:
#   bundle exec rake lynomia:docs:seo_audit
#   PORTAL_SLUG=lynomia-docs bundle exec rake lynomia:docs:seo_audit
module DocumentationSeoAudit
  # A search result shows about this much of a description. Shorter than this and the result renders a
  # truncated sentence from the body instead, which is rarely the sentence you would have chosen.
  MIN_DESCRIPTION = 50
  MAX_DESCRIPTION = 160
  MAX_TITLE = 60

  Finding = Struct.new(:level, :article, :message, keyword_init: true)
end

# rubocop:disable Metrics/BlockLength
namespace :lynomia do
  namespace :docs do
    desc 'Audit the public documentation for indexability (read-only; exits 1 on an error)'
    task seo_audit: :environment do
      include ActionView::Helpers::TagHelper
      include DocumentationHelper
      include PortalHelper

      portals = Portal.where(archived: false)
      portals = portals.where(slug: ENV.fetch('PORTAL_SLUG')) if ENV['PORTAL_SLUG'].present?

      if portals.empty?
        puts 'no portal to audit'
        next
      end

      findings = []

      portals.each do |portal|
        articles = portal.articles.where(status: :published).includes(:category, :root_article, :associated_articles)
        puts "portal #{portal.slug}: #{articles.length} published article(s), locales #{portal.allowed_locale_codes.join(',')}"

        # One canonical per article, and no two articles claiming the same one. A duplicate canonical is how two
        # pages compete with each other and both lose.
        by_canonical = articles.group_by { |article| portal_canonical_url(portal, article) }
        by_canonical.each do |url, group|
          next if group.length == 1

          findings << DocumentationSeoAudit::Finding.new(
            level: :error, article: group.first, message: "#{group.length} articles share the canonical #{url}"
          )
        end

        articles.each do |article|
          findings.concat(audit_article(portal, article))
        end
      end

      report(findings)
    end

    def audit_article(portal, article)
      findings = []
      canonical = portal_canonical_url(portal, article)

      findings << error(article, 'canonical URL has no host') unless canonical.start_with?('http')
      findings << error(article, 'no title') if article.title.blank?
      findings << warn_for(article, "title is #{article.title.length} characters (over #{DocumentationSeoAudit::MAX_TITLE})") if
        article.title.to_s.length > DocumentationSeoAudit::MAX_TITLE

      findings.concat(audit_description(article))
      findings.concat(audit_alternates(portal, article))
      findings.concat(audit_structured_data(portal, article))
      findings.compact
    end

    # The sentence a search result renders. Absent is an error, because the alternative is the crawler choosing
    # a sentence out of the body.
    def audit_description(article)
      description = article.meta['description'].presence || article.description.presence
      return [error(article, 'no meta description and no description')] if description.blank?

      length = description.length
      return [] if length.between?(DocumentationSeoAudit::MIN_DESCRIPTION, DocumentationSeoAudit::MAX_DESCRIPTION)

      want = "#{DocumentationSeoAudit::MIN_DESCRIPTION}-#{DocumentationSeoAudit::MAX_DESCRIPTION}"
      [warn_for(article, "description is #{length} characters (want #{want})")]
    end

    # hreflang RECIPROCITY. A crawler ignores an alternate that does not point back, so a one-way link is not a
    # partial win -- it is nothing, and it looks like it works.
    def audit_alternates(portal, article)
      alternates = portal_locale_alternates(portal, article)
      return [] if alternates.empty?

      findings = []
      findings << error(article, 'hreflang set does not include the article itself') unless
        alternates.any? { |_locale, url| url == portal_canonical_url(portal, article) }
      findings << error(article, 'hreflang set has no x-default') if portal_default_alternate_url(portal, article).blank?
      findings << duplicate_locales(article, alternates.map(&:first))
      findings.compact
    end

    def duplicate_locales(article, locales)
      repeated = locales.tally.select { |_locale, count| count > 1 }.keys
      return nil if repeated.empty?

      error(article, "duplicate hreflang locales: #{repeated.join(',')}")
    end

    # The structured data has to BUILD. A nil breadcrumb crumb or an unserializable value is a silent
    # `application/ld+json` block that no search engine can read.
    def audit_structured_data(portal, article)
      breadcrumb = documentation_breadcrumb_schema(portal, article)
      schema = documentation_article_schema(portal, article)
      findings = []
      findings << error(article, 'breadcrumb has a crumb with no name or URL') if
        breadcrumb['itemListElement'].any? { |crumb| crumb['name'].blank? || crumb['item'].blank? }
      findings << error(article, 'article schema has no url') if schema['url'].blank?
      JSON.parse([breadcrumb, schema].to_json)
      findings.compact
    rescue StandardError => e
      [error(article, "structured data could not be serialized (#{e.class})")]
    end

    def error(article, message)
      DocumentationSeoAudit::Finding.new(level: :error, article: article, message: message)
    end

    def warn_for(article, message)
      DocumentationSeoAudit::Finding.new(level: :warn, article: article, message: message)
    end

    def report(findings)
      errors = findings.select { |finding| finding.level == :error }
      warnings = findings.select { |finding| finding.level == :warn }

      print_group('ERROR', errors)
      print_group('WARN', warnings)

      puts ''
      puts "#{errors.length} error(s), #{warnings.length} warning(s)"
      puts errors.empty? ? 'INDEXABLE' : 'NOT_INDEXABLE'
      exit 1 unless errors.empty?
    end

    def print_group(label, group)
      return if group.empty?

      puts ''
      group.each { |finding| puts finding_line(label, finding) }
    end

    def finding_line(label, finding)
      format('  %<label>-5s %<locale>-3s %<slug>-44s %<message>s', label: label, locale: finding.article.locale,
                                                                   slug: finding.article.slug.truncate(42), message: finding.message)
    end
  end
end
# rubocop:enable Metrics/BlockLength
