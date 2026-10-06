# Lynomia global documentation (docs/global-documentation/01-global-ownership-design.md): the one door onto platform
# content, so the public routes, Super Admin, the contextual-help registry and the seeder all agree about what the
# documentation and changelog portals are.
#
# A platform portal belongs to no account, which is what keeps it out of every tenant surface -- each one reads
# through `Current.account.portals`, and no NULL account_id can satisfy that.
class Documentation::Library
  DOCS_SLUG = 'lynomia-docs'.freeze
  CHANGELOG_SLUG = 'lynomia-changelog'.freeze
  SLUGS = [DOCS_SLUG, CHANGELOG_SLUG].freeze

  # The two languages the product ships. A portal's own allowed_locales stays authoritative at render time; this is
  # what the seeder sets them to.
  LOCALES = %w[en ar].freeze
  DEFAULT_LOCALE = 'en'.freeze

  class << self
    def docs_portal
      platform_portal(DOCS_SLUG)
    end

    def changelog_portal
      platform_portal(CHANGELOG_SLUG)
    end

    # Raises when the portal is missing, because on a deployed install its absence is a setup bug rather than a
    # state the product should route around.
    def docs_portal!
      docs_portal || raise(ActiveRecord::RecordNotFound, "Lynomia documentation portal '#{DOCS_SLUG}' is not set up")
    end

    def changelog_portal!
      changelog_portal || raise(ActiveRecord::RecordNotFound,
                                "Lynomia changelog portal '#{CHANGELOG_SLUG}' is not set up")
    end

    def portals
      Portal.platform.active.where(slug: SLUGS)
    end

    # Every published platform article, for search scoping and for the link registry's resolution check.
    def articles
      Article.published.where(portal: portals)
    end

    def article(slug)
      articles.find_by(slug: slug)
    end

    # Resolves a contextual-help key to the article in the reader's language, falling back to the default locale when
    # that language has no translation yet, and finally treating the key as a literal slug.
    # `articles.slug` is globally unique, so one key cannot be the slug in more than one locale -- the key lives in
    # `meta` instead (docs/global-documentation/12-contextual-help.md).
    def article_for(key, locale: nil)
      by_key = articles.where("articles.meta->>'doc_key' = ?", key)
      by_key.find_by(locale: locale) || by_key.find_by(locale: DEFAULT_LOCALE) || by_key.first || article(key)
    end

    private

    def platform_portal(slug)
      Portal.platform.active.find_by(slug: slug)
    end
  end
end
