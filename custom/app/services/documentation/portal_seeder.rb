# Lynomia global documentation: creates the two platform portals, idempotently, and points the product's own
# documentation and changelog links at them.
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

  # Where the dashboard's documentation and changelog links point once this installation serves them itself. The
  # routes are in config/routes/documentation.rb.
  LINKS = { 'DOCUMENTATION_URL' => '/docs', 'CHANGELOG_URL' => '/changelog' }.freeze

  def perform!
    PORTALS.map { |attributes| create_or_update(attributes) }.tap { point_product_links_here }
  end

  private

  # ConfigLoader creates an installation config once and never overwrites it, so an installation that existed before
  # these keys did keeps them blank -- and a blank DOCUMENTATION_URL hides every documentation link in the dashboard.
  # Seeding the portals is the moment the installation starts serving its own documentation, so it is the moment the
  # links should point at it. Only a blank value is filled: an operator who has pointed these at a documentation site
  # of their own keeps that.
  def point_product_links_here
    LINKS.each do |name, path|
      config = InstallationConfig.find_by(name: name)
      next if config.nil? || config.value.present?

      config.update!(value: path)
    end
    GlobalConfig.clear_cache
  end

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
