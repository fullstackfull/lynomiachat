# Is the public documentation actually indexable? (docs/product-refinement/03-documentation-seo.md)
#
# IN `lib/` AND NOT IN THE `.rake` FILE, which is not a style choice. `Rakefile` does `require_relative
# 'config/application'` and then `load_tasks` -- it never initializes the application, so Zeitwerk's autoloaders
# are not set up while a `.rake` file is being read. A class body in a `.rake` file that says
# `include DocumentationHelper` therefore dereferences that constant with no autoloader present, raises
# NameError out of `load_tasks`, and breaks EVERY rake task in the project, `db:migrate` and
# `assets:precompile` included. `lib` is an eager load path (config/application.rb:42), so living here makes
# this module autoload the first time the task body -- which depends on `:environment` -- names it.
#
#
# WHY A TASK AND NOT A SPEC. A spec asserts the TEMPLATE emits a canonical tag. This asserts that THIS
# installation's content, as seeded and edited, produces addresses a crawler can use: that no two pages claim
# the same canonical, that every hreflang points at a published sibling that points back, that nothing is
# missing the description a search result renders, and that every contextual-help key the product links still
# resolves to the article it names. Those are facts about data, so they have to be checked against data, on the
# server that serves it.
#
# WHAT THIS TASK DROPPED, AND WHY IT IS NOT A LOSS. Eight of the ten ERROR checks it used to run could not fail
# (discovery/098-attack-seo-indexability.md R1): `no title` is `validates :title, presence: true`
# (app/models/article.rb:67); `hreflang set does not include the article itself` and `hreflang set has no
# x-default` are both excluded by the early return above them; `breadcrumb has a crumb with no name or URL`
# and `article schema has no url` are presence-validated or built strings; `structured data could not be
# serialized` cannot raise over `text` columns in a UTF-8 database. A clean `INDEXABLE` from those checks was a
# measurement of nothing, and `01-current-system.md` §10 reads the exit code as meaning something. They are
# properties of code, so they belong in spec/helpers/documentation_helper_spec.rb, and that is where they now
# are. What is left is only checks that can fail on real rows -- and `canonical URL has no host`, which was
# inverted and is now a real check (R4).
#
# `N articles share the canonical` went with them, and it is the one worth proving rather than citing, because
# extending the audit to category pages looked like it would make the check reachable and does not. A canonical
# is host + `/hc/<portal.slug>/articles/<article.slug>` or host + `/hc/<portal.slug>/<locale>/categories/<slug>`
# (custom/app/helpers/documentation_helper.rb). `index_portals_on_slug` is UNIQUE (db/schema.rb:1792) and so is
# `validates :slug, uniqueness: true` (app/models/portal.rb:70), so the path prefix identifies the portal;
# `index_articles_on_slug` is UNIQUE (db/schema.rb:226) globally; and
# `index_categories_on_slug_and_locale_and_portal_id` is UNIQUE (db/schema.rb:665) per portal. An article URL
# and a category URL cannot collide either -- one has `/articles/`, the other `/<locale>/categories/`. Two
# portals sharing a `custom_domain` cannot collide because the portal slug is still in the path, and
# `index_portals_on_custom_domain` is UNIQUE anyway (db/schema.rb:1790). The database makes a duplicate
# canonical unrepresentable, so the check could only ever fail by stubbing the model -- which is exactly how
# its one spec example passed (098 R5).
#
# READ-ONLY. It writes nothing and fixes nothing. Exit status is 1 when there is an ERROR so an operator sees
# failure; warnings do not fail it. It is NOT a deploy gate: it audits content that is already committed and
# already public, so failing a healthy revision on a short meta description would be disproportionate
# (P2-SOURCE-OF-TRUTH-CONTRACT.md D11).
#
# Usage:
#   bundle exec rake lynomia:docs:seo_audit
#   PORTAL_SLUG=lynomia-docs bundle exec rake lynomia:docs:seo_audit
module DocumentationSeoAudit
  # A search result shows about this much of a description. Shorter than this and the result renders a
  # truncated sentence from the body instead, which is rarely the sentence you would have chosen.
  MIN_DESCRIPTION = 50
  MAX_DESCRIPTION = 160
  # Applied to the RENDERED `<title>`, which is `article.title` plus the portal's own page title. Measuring
  # `article.title` alone under-reported the corpus by the length of that suffix (098 R2, R3).
  MAX_TITLE = 60
  # An image whose alt text is empty publishes an inaccessible image AND an empty public search snippet,
  # because `render_markdown_to_plain_text` emits an image's alt text and discards its URL, and that is what
  # the public `articles.json` `content` field carries (R2-MEDIA-CONTRACT.md §0.3, item 7).
  EMPTY_ALT_IMAGE = /!\[[[:space:]]*\]\(/

  Finding = Struct.new(:level, :article, :message, keyword_init: true)

  # A finding about something that is not an Article still has to print in the report, so a category and a
  # portal borrow the two fields the formatter reads.
  Subject = Struct.new(:locale, :slug)

  # Everything the task does, in a class rather than in `def`s inside the Rake block: those define methods on
  # Object, and this one needs the real view helpers so that every address it measures is built by exactly the
  # code the templates use. Re-deriving a canonical or a `<title>` here would make the audit able to pass while
  # the page is wrong, which is the failure mode 098 R2 and R4 are both instances of.
  class Auditor
    include DocumentationHelper
    include PortalHelper

    def initialize(portals)
      @portals = portals
      @findings = []
    end

    def perform
      @portals.each { |portal| audit_portal(portal) }
      # `duplicate_locales` returns nil when there is nothing to report, which is what makes it readable at
      # both call sites; the compaction is here so neither of them has to say so.
      @findings.compact
    end

    private

    attr_reader :portals, :findings

    def audit_portal(portal)
      articles = portal.articles.where(status: :published).includes(:category, :root_article, :associated_articles)
      # Live progress for an operator watching a CLI audit run, which is why stdout and not the logger: the
      # reader is a person at a terminal, and buffering this into the final report would lose the per-portal
      # heartbeat on a large corpus. The cop does not apply to `.rake` files, where this line used to live --
      # moving the class into `lib/` is what brought it into scope, not a change in what it does.
      # rubocop:disable Rails/Output
      puts "portal #{portal.slug}: #{articles.length} published article(s), " \
           "#{portal.categories.length} category(ies), locales #{portal.allowed_locale_codes.join(',')}"
      # rubocop:enable Rails/Output

      audit_host(portal)
      articles.each { |article| audit_article(portal, article) }
      portal.categories.each { |category| audit_category(portal, category) }
      audit_locale_coverage(portal, articles) if portal.platform_owned?
      audit_doc_keys(articles) if portal.platform_owned?
    end

    # ONCE PER PORTAL, not once per page, because the host is a property of the portal: every canonical,
    # hreflang, `og:url`, JSON-LD `url` and sitemap `<loc>` it publishes is wrong together or right together.
    # Per page this printed the same line for every row and buried everything else.
    #
    # `start_with?('http')` was true for `https://hc/hc/...`, the string a blank host used to produce, so this
    # check passed on the one misconfiguration it existed to catch (098 R4). `portal_absolute_url` now returns
    # a root-relative path rather than inventing a hostname, which is what makes this reachable.
    def audit_host(portal)
      sample = portal_home_url(portal, portal.default_locale)
      return if absolute_with_host?(sample)

      findings << error(Subject.new(portal.default_locale, portal.slug),
                        'no host: neither the portal custom_domain nor HELPCENTER_URL/FRONTEND_URL is set, so ' \
                        "every canonical on this portal is relative (#{sample})")
    end

    def audit_article(portal, article)
      audit_rendered_title(portal, article)
      audit_description(article)
      audit_duplicate_hreflang_locales(portal, article)
      audit_image_alt_text(article)
    end

    # A category page is a page: it has its own canonical and its own `<meta name="description">`
    # (documentation_layout/categories/_meta_head.html.erb:11,14) and nothing checked either. Only the
    # description is checkable -- `Category` does not validate it, and the seeder takes it from the manifest
    # section, so an added section can arrive without one and an operator can clear it.
    #
    # A warning rather than an error, and the asymmetry with an article is deliberate: a section page's content
    # is the list of article titles under it, which is a usable snippet on its own. An article with no
    # description leaves a crawler nothing but prose to cut a sentence out of.
    #
    # Its hreflang set is NOT checked, for the same reason the duplicate-canonical check is gone:
    # `index_categories_on_slug_and_locale_and_portal_id` is UNIQUE (db/schema.rb:665) and
    # `portal_category_locale_alternates` groups by exactly that pair, so a duplicate locale in the set is
    # unrepresentable.
    def audit_category(portal, category)
      return if category.description.present?
      return unless portal.allowed_locale_codes.include?(category.locale)

      findings << warn_for(Subject.new(category.locale, "categories/#{category.slug}"),
                           'no description, so this section page has no meta description')
    end

    # THE LENGTH A SEARCH RESULT TRUNCATES. `meta['title']` does not reach `<title>` -- it overrides only
    # `<meta name="title">`, `og:title` and `twitter:title` -- so an author who writes a short `seo_title` has
    # not fixed this, and treating those articles as compliant silences the warning on exactly the pages that
    # need it (098 R2). The suffix length is in the message because it is the part the author cannot shorten.
    def audit_rendered_title(portal, article)
      rendered = documentation_page_title(portal, article)
      return if rendered.length <= MAX_TITLE

      suffix = rendered.length - article.title.to_s.length
      findings << warn_for(article, "rendered <title> is #{rendered.length} characters (over #{MAX_TITLE}; " \
                                    "#{suffix} of them are the portal suffix)")
    end

    # The sentence a search result renders. Absent is an error, because the alternative is the crawler choosing
    # a sentence out of the body.
    def audit_description(article)
      description = article.meta['description'].presence || article.description.presence
      if description.blank?
        findings << error(article, 'no meta description and no description')
        return
      end

      return if description.length.between?(MIN_DESCRIPTION, MAX_DESCRIPTION)

      findings << warn_for(article, "description is #{description.length} characters (want #{MIN_DESCRIPTION}-#{MAX_DESCRIPTION})")
    end

    # hreflang RECIPROCITY, the half of it that can fail. Two rows of one translation family claiming the same
    # locale makes the whole set ambiguous, and it is reachable: moving an article into a category of another
    # locale has `ensure_locale_in_article` (app/models/article.rb) rewrite the article's locale to match.
    def audit_duplicate_hreflang_locales(portal, article)
      findings << duplicate_locales(article, portal_locale_alternates(portal, article).map(&:first))
    end

    def duplicate_locales(subject, locales)
      repeated = locales.tally.select { |_locale, count| count > 1 }.keys
      return nil if repeated.empty?

      error(subject, "duplicate hreflang locales: #{repeated.join(',')}")
    end

    # HREFLANG COVERAGE, which is the gap an after-the-fact audit is actually for: a corpus that has lost its
    # Arabic siblings produces a perfectly valid set of English-only pages, so every reciprocity check passes
    # and the portal silently stops serving half its readers. A warning rather than an error, because a
    # translation that has not been written yet is a content state, not a broken address.
    def audit_locale_coverage(portal, articles)
      default = portal.default_locale
      others = portal.allowed_locale_codes - [default]
      return if others.empty?

      articles.select { |article| article.locale == default }.each do |article|
        family_locales = portal_locale_alternates(portal, article).map(&:first)
        (others - family_locales).each do |missing|
          findings << warn_for(article, "no published #{missing} sibling, so this page has no hreflang for #{missing}")
        end
      end
    end

    # THE CONTEXTUAL-HELP CONTRACT, checked against the database rather than against the files.
    #
    # `meta['doc_key']` is what every in-product help link resolves through
    # (Documentation::Library#article_for), and it is the one field the corpus writes that no Super Admin form
    # input carries -- so a save that replaces `meta` wholesale deletes it and nothing visible breaks until a
    # reader clicks Learn more (P2-WORKSTREAM-OWNERSHIP.md §E1). A file-level spec cannot see that, because the
    # file still has the key. Three distinct failures, and the third subsumes the first two for one row while
    # still being worth reporting separately, because the messages are what tell an operator what happened.
    def audit_doc_keys(articles)
      claimants = articles.group_by { |article| [article.locale, article.meta['doc_key']] }
      articles.each { |article| audit_doc_key(article, claimants) }
    end

    def audit_doc_key(article, claimants)
      key = article.meta['doc_key']
      return findings << error(article, 'no doc_key, so every in-product link to this article is broken') if key.blank?

      claiming = claimants[[article.locale, key]].map(&:slug)
      return findings << error(article, "doc_key '#{key}' is claimed by #{claiming.join(', ')}") if claiming.length > 1

      resolved = Documentation::Library.article_for(key, locale: article.locale)
      return if resolved&.id == article.id

      findings << error(article, "doc_key '#{key}' resolves to #{resolved&.slug.inspect}, not to this article")
    end

    # Alt text is a public SEO field on these pages, not only an accessibility attribute. The seed boundary
    # already refuses an empty alt in a corpus file, so this is not a second copy of that rule -- it is the
    # only check on an image an operator inserted in Super Admin, which never passes the seed boundary at all.
    def audit_image_alt_text(article)
      count = article.content.to_s.scan(EMPTY_ALT_IMAGE).length
      return if count.zero?

      findings << error(article, "#{count} image(s) with empty alt text, which publish an empty search snippet")
    end

    # A canonical a crawler can use is absolute and names a host.
    def absolute_with_host?(url)
      uri = URI.parse(url)
      uri.scheme.present? && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def error(subject, message)
      Finding.new(level: :error, article: subject, message: message)
    end

    def warn_for(subject, message)
      Finding.new(level: :warn, article: subject, message: message)
    end
  end
end
