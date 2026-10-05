# Lynomia global documentation: seeds the documentation corpus from source control into the platform portal.
#
# One-time, operator-run, idempotent: `rails documentation:content`. Not a scraper and not a background job -- the
# content lives in this repository as Markdown with YAML front matter, is reviewed the way code is reviewed, and is
# upserted by slug so re-running it updates rather than duplicates.
#
# An operator's own edits in Super Admin are not protected from a re-run: the files are the source, and a change that
# should survive belongs in a file. The seeder says what it changed so that is visible rather than silent.
class Documentation::ContentSeeder
  DOCS_ROOT = Rails.root.join('custom/db/documentation')
  CHANGELOG_ROOT = Rails.root.join('custom/db/changelog')
  FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n/m

  Result = Struct.new(:created, :updated, :unchanged, :locales, keyword_init: true)

  def self.changelog
    new(portal: Documentation::Library.changelog_portal!, root: CHANGELOG_ROOT)
  end

  def initialize(portal: nil, author: nil, publish: true, root: DOCS_ROOT)
    @portal = portal || Documentation::Library.docs_portal!
    @author = author || SuperAdmin.first || raise(ArgumentError, 'A super admin is required to author documentation')
    @publish = publish
    @root = root
    @result = Result.new(created: 0, updated: 0, unchanged: 0, locales: [])
  end

  def perform!
    manifest['sections'].each { |section| seed_section(section) }
    @result
  end

  private

  attr_reader :portal, :author, :root

  def manifest
    @manifest ||= YAML.load_file(root.join('manifest.yml'))
  end

  # The default locale is seeded first, because every other locale links its translation to that article.
  def locales
    @locales ||= (Documentation::Library::LOCALES & portal.allowed_locale_codes)
                 .sort_by { |locale| locale == Documentation::Library::DEFAULT_LOCALE ? 0 : 1 }
  end

  def seed_section(section)
    locales.each do |locale|
      next unless section[locale]

      category = upsert_category(section, locale)
      Dir.glob(root.join(locale, section['slug'], '*.md')).each do |path|
        upsert_article(path, category, locale)
      end
    end
  end

  def upsert_category(section, locale)
    category = portal.categories.find_or_initialize_by(slug: section['slug'], locale: locale)
    category.assign_attributes(name: section[locale]['name'], description: section[locale]['description'],
                               position: section['position'], icon: section['icon'].to_s)
    category.save!
    category
  end

  # `articles.slug` is globally unique, so the English and Arabic versions of one article cannot share it. The file
  # name is the article's stable KEY -- what a product link in the dashboard points at -- and each locale gets a slug
  # derived from it. The key is stored in `meta` so the key-to-locale lookup is one query
  # (docs/global-documentation/12-contextual-help.md).
  def upsert_article(path, category, locale)
    front_matter, body = split(File.read(path))
    key = File.basename(path, '.md')
    article = portal.articles.find_or_initialize_by(slug: slug_for(key, locale), locale: locale)
    was_new = article.new_record?

    article.assign_attributes(attributes_for(front_matter, body, category, key))
    article.associated_article_id = root_article_id(key) unless locale == Documentation::Library::DEFAULT_LOCALE
    changed = article.changed?
    article.author ||= author
    article.save!

    count(was_new, changed)
  end

  def slug_for(key, locale)
    locale == Documentation::Library::DEFAULT_LOCALE ? key : "#{key}-#{locale}"
  end

  # Translations hang off the default-locale article, which is how the Help Center already links them.
  def root_article_id(key)
    portal.articles.find_by(slug: key, locale: Documentation::Library::DEFAULT_LOCALE)&.id
  end

  def attributes_for(front_matter, body, category, key)
    {
      title: front_matter.fetch('title'),
      description: front_matter['description'],
      content: body,
      category: category,
      position: front_matter.fetch('position'),
      status: @publish ? :published : :draft,
      meta: meta_for(front_matter, key)
    }
  end

  def meta_for(front_matter, key)
    { 'doc_key' => key,
      'title' => front_matter['seo_title'].presence || front_matter.fetch('title'),
      'description' => front_matter['seo_description'].presence || front_matter['description'],
      'tags' => Array(front_matter['tags']),
      'version' => front_matter['version'].presence,
      'release_date' => front_matter['release_date'].presence&.to_s }.compact
  end

  def count(was_new, changed)
    if was_new
      @result.created += 1
    elsif changed
      @result.updated += 1
    else
      @result.unchanged += 1
    end
  end

  # The front matter carries what the Help Center stores in columns and in `meta`; everything after it is the article.
  def split(source)
    match = source.match(FRONT_MATTER)
    raise ArgumentError, 'A documentation article needs YAML front matter' if match.nil?

    [YAML.safe_load(match[1], permitted_classes: [Date]), match.post_match.strip]
  end
end
