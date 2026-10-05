# Lynomia global documentation: creates the two platform portals, idempotently.
#
# Run from `rails documentation:setup`. Safe to re-run: it matches on slug and updates presentation, so an operator who
# has renamed a portal in Super Admin does not lose that on the next deploy -- only the fields that define the portal's
# identity and language set are enforced.
class Documentation::PortalSeeder
  PORTALS = [
    {
      slug: Documentation::Library::DOCS_SLUG,
      name: 'Lynomia Chat Documentation',
      page_title: 'Lynomia Chat Documentation',
      header_text: 'Guides for setting up and running Lynomia Chat.'
    },
    {
      slug: Documentation::Library::CHANGELOG_SLUG,
      name: 'Lynomia Chat Changelog',
      page_title: 'Lynomia Chat Changelog',
      header_text: "What's new in Lynomia Chat.",
      article_order: 'release_date'
    }
  ].freeze

  def perform!
    PORTALS.map { |attributes| create_or_update(attributes) }
  end

  private

  def create_or_update(attributes)
    attributes = attributes.dup
    portal_config = config.merge('article_order' => attributes.delete(:article_order) || 'position')
    portal = Portal.find_by(slug: attributes[:slug])
    return Portal.create!(attributes.merge(platform_owned: true, config: portal_config)) if portal.nil?

    portal.update!(platform_owned: true, account: nil,
                   config: portal_config.merge(portal.config.to_h.slice('layout')))
    portal
  end

  # Documentation reads better in the documentation layout than in the support-style classic one, and both languages
  # are public from the start -- an Arabic reader should never land on a locale the portal calls a draft.
  def config
    { 'allowed_locales' => Documentation::Library::LOCALES,
      'default_locale' => Documentation::Library::DEFAULT_LOCALE,
      'layout' => 'documentation' }
  end
end
