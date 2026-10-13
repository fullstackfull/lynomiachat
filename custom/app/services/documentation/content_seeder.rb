# Lynomia global documentation: seeds the documentation corpus from source control into the platform portal.
#
# One-time, operator-run, idempotent: `rails documentation:content`. Not a scraper and not a background job -- the
# content lives in this repository as Markdown with YAML front matter, is reviewed the way code is reviewed, and is
# upserted by slug so re-running it updates rather than duplicates.
#
# SOURCE OF TRUTH IS FIELD BY FIELD, not all-or-nothing, because nine fields have two writers: this seeder and the
# Super Admin form (custom/app/dashboards/article_dashboard.rb FORM_ATTRIBUTES). A deploy must never silently
# revert an operator's edit, so each field is classified and the seeder obeys the classification
# (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md section 2):
#
#   D  identity/provenance  portal, locale, meta['doc_key'], content_source_path
#                           Repository-owned and reasserted on every run. An operator cannot reach them: `slug` and
#                           `locale` are the lookup, `doc_key` is the file's basename, the path is this file.
#   A  repository-owned     content, category, associated_article_id
#                           Prose and placement come from the corpus. The seeder wins on every run.
#   B  operator-owned       status
#                           The file does not express it. Written on create only, so an operator who unpublishes an
#                           article stays unpublished across a deploy.
#   C  mergeable per field  title, description, position, meta title/description/tags/version/release_date
#                           Written only while the row still holds what the seeder last wrote there -- or already
#                           holds what the file says, which is the same content and re-attaches the field. Anything
#                           else is an operator's edit: left alone and REPORTED, per article and per field.
#
# `seeded_digests` is what makes class C decidable: one SHA-256 per field of the value the seeder last wrote
# there. It is a digest, never the value, so this is not a second copy of the content and not a revision store.
class Documentation::ContentSeeder
  DOCS_ROOT = Rails.root.join('custom/db/documentation')
  CHANGELOG_ROOT = Rails.root.join('custom/db/changelog')
  FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n/m

  MERGEABLE_COLUMNS = %w[title description position].freeze
  MERGEABLE_META_KEYS = %w[title description tags version release_date].freeze
  MERGEABLE_FIELDS = (MERGEABLE_COLUMNS + MERGEABLE_META_KEYS.map { |key| "meta.#{key}" }).freeze

  # First element of every digest payload. Changing what a digest covers has to invalidate every stored digest, and
  # that turns the whole corpus untracked on the next run -- a loud, operator-gated event rather than a silent
  # reclassification. NEVER change the payload without bumping this.
  DIGEST_VERSION = 1

  # created/updated/unchanged/adopted/untracked are mutually exclusive outcomes, one per file processed, so they
  # reconcile against the corpus. `divergences` is the per-field detail behind them.
  Result = Struct.new(:created, :updated, :unchanged, :adopted, :untracked, :locales, :divergences,
                      keyword_init: true)
  Divergence = Struct.new(:kind, :locale, :slug, :path, :fields, keyword_init: true)

  # One corpus file, parsed. `columns` and `meta` hold only the class-C fields, which is what keeps the merge and the
  # digests reading from the same two hashes instead of from two shapes that can drift apart.
  FileState = Struct.new(:locale, :category, :body, :doc_key, :source_path, :columns, :meta, keyword_init: true) do
    def default_locale? = locale == Documentation::Library::DEFAULT_LOCALE
  end

  def self.changelog(**)
    new(portal: Documentation::Library.changelog_portal!, root: CHANGELOG_ROOT, **)
  end

  def initialize(portal: nil, author: nil, publish: true, root: DOCS_ROOT, adopt_untracked: false)
    @portal = portal || Documentation::Library.docs_portal!
    @author = author || SuperAdmin.first || raise(ArgumentError, 'A super admin is required to author documentation')
    @publish = publish
    @root = root
    @adopt_untracked = adopt_untracked
    @result = Result.new(created: 0, updated: 0, unchanged: 0, adopted: 0, untracked: 0, locales: [], divergences: [])
  end

  def perform!
    manifest['sections'].each { |section| seed_section(section) }
    @result.locales = locales
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
  #
  # The lookup stays `(slug, locale)`: `slug` left ArticleDashboard::FORM_ATTRIBUTES in wave 2 and no live path
  # writes it on an existing row, so it is as stable an identity as the provenance column would be
  # (P2-SOURCE-OF-TRUTH-CONTRACT.md D4).
  def upsert_article(path, category, locale)
    file = read_file(path, category, locale)
    article = portal.articles.find_or_initialize_by(slug: slug_for(file.doc_key, locale), locale: locale)
    adopting = article.persisted? && article.seeded_digests.blank?
    return record_untracked(file) if adopting && !@adopt_untracked

    kept = article.new_record? || adopting ? [] : operator_fields(article, file)
    changed = apply(article, file, kept)
    record(article, file, kept, adopting: adopting, changed: changed)
  end

  def slug_for(key, locale)
    locale == Documentation::Library::DEFAULT_LOCALE ? key : "#{key}-#{locale}"
  end

  # Translations hang off the default-locale article, which is how the Help Center already links them.
  def root_article_id(key)
    portal.articles.find_by(slug: key, locale: Documentation::Library::DEFAULT_LOCALE)&.id
  end

  # Returns true when the row was written.
  def apply(article, file, kept)
    assign(article, file, kept)
    changed = article.changed?
    intended_position = article.position
    article.save!
    converge_position(article, intended_position)
    changed
  end

  # Everything the seeder is allowed to write, in one place and in class order: A, then B on create only, then C
  # for the fields the operator has not taken over, then the digests of what this run wrote.
  def assign(article, file, kept)
    article.assign_attributes(content: file.body, category: file.category, content_source_path: file.source_path)
    article.associated_article_id = root_article_id(file.doc_key) unless file.default_locale?
    article.status = @publish ? :published : :draft if article.new_record?
    MERGEABLE_COLUMNS.each { |column| article[column] = file.columns[column] unless kept.include?(column) }
    article.meta = merged_meta(article, file, kept)
    article.seeded_digests = digests_for(article, file, kept)
    article.author ||= author
  end

  # `doc_key` is class D: the corpus owns it and reasserts it, because it is the identity every contextual-help link
  # resolves through (custom/app/services/documentation/library.rb:63). Every other key on the column belongs to
  # whoever last wrote it -- `feature_image` is the form's alone -- so the hash is merged key by key and never
  # replaced, which is the same rule ArticleMetaField.merge_submitted applies from the other side.
  def merged_meta(article, file, kept)
    meta = article.meta.to_h
    meta['doc_key'] = file.doc_key
    MERGEABLE_META_KEYS.each do |key|
      next if kept.include?("meta.#{key}")

      if file.meta[key].nil?
        meta.delete(key)
      else
        meta[key] = file.meta[key]
      end
    end
    meta
  end

  # The class-C fields this run must leave alone. A field is the seeder's while the row still holds the value the
  # seeder last wrote there, and also when the row already holds what the file says -- the second clause is what
  # lets a row converge again after an operator and the corpus arrive at the same text independently, instead of
  # reporting a divergence that no longer exists.
  def operator_fields(article, file)
    MERGEABLE_FIELDS.reject do |field|
      current = digest(field, current_value(article, field))
      current == article.seeded_digests[field] || current == digest(field, file_value(file, field))
    end
  end

  def digests_for(article, file, kept)
    MERGEABLE_FIELDS.index_with do |field|
      kept.include?(field) ? article.seeded_digests[field] : digest(field, file_value(file, field))
    end.compact
  end

  def digest(field, value)
    canonical = value.is_a?(Array) ? value.map(&:to_s) : value.to_s
    Digest::SHA256.hexdigest(JSON.generate([DIGEST_VERSION, field, canonical]))
  end

  def current_value(article, field)
    column, key = field.split('.')
    key ? article.meta.to_h[key] : article[column]
  end

  def file_value(file, field)
    column, key = field.split('.')
    key ? file.meta[key] : file.columns[column]
  end

  # THE ONE WRITE THAT REPAIRS ANOTHER WRITE, and the only one in this file.
  #
  # `Article` re-derives `position` as `max + 10` in an after_save whenever `category_id` changed
  # (app/models/article.rb:74,274-284) -- which is exactly what a corpus file moving between manifest sections
  # does. MEASURED on a two-section fixture: after the move the row holds `max + 10` instead of the authored
  # position, and the authored value only returns on a SECOND run, so one run was not convergent.
  #
  # Repaired here rather than in the model: that callback is product-wide and a tenant Help Center legitimately
  # wants the end-of-category default, and a guard inside it was measured never to execute on a stable corpus
  # (P2-WORKSTREAM-OWNERSHIP.md E2), which makes it a guard on a path that does not run. This writes only when the
  # save actually moved the position away from the value this run decided on -- the file's when the corpus owns the
  # field, the operator's when they do.
  def converge_position(article, intended_position)
    return if intended_position.nil? || article.position == intended_position

    article.update_column(:position, intended_position) # rubocop:disable Rails/SkipsModelValidations
  end

  def record(article, file, kept, adopting:, changed:)
    @result.divergences << divergence(:operator_edited, file, kept) if kept.any?
    @result[outcome(article, adopting, changed)] += 1
  end

  # One outcome per file processed, so created + updated + unchanged + adopted + untracked reconciles against the
  # corpus on disk. A row can be `updated` and carry a divergence in the same run: class A is written while a
  # class-C field the operator owns is left alone.
  def outcome(article, adopting, changed)
    return :created if article.previously_new_record?
    return :adopted if adopting

    changed ? :updated : :unchanged
  end

  # A row the seeder has never tracked: `seeded_digests` is empty, so there is no way to tell a previous seed's own
  # writing from an operator's. Writing it would be exactly the silent overwrite this design exists to prevent, so
  # the run reports it and leaves it, and `ADOPT_UNTRACKED=1` is the operator saying once, by hand, that the corpus
  # wins (P2-SOURCE-OF-TRUTH-CONTRACT.md D7).
  def record_untracked(file)
    @result.divergences << divergence(:untracked, file, [])
    @result.untracked += 1
  end

  def divergence(kind, file, fields)
    Divergence.new(kind: kind, locale: file.locale, slug: slug_for(file.doc_key, file.locale),
                   path: file.source_path, fields: fields)
  end

  def read_file(path, category, locale)
    front_matter, body = split(File.read(path))
    FileState.new(
      locale: locale, category: category, body: body, doc_key: File.basename(path, '.md'),
      source_path: Pathname.new(path).relative_path_from(Rails.root).to_s,
      columns: { 'title' => front_matter.fetch('title'), 'description' => front_matter['description'],
                 'position' => front_matter.fetch('position') },
      meta: { 'title' => front_matter['seo_title'].presence || front_matter.fetch('title'),
              'description' => front_matter['seo_description'].presence || front_matter['description'],
              'tags' => Array(front_matter['tags']), 'version' => front_matter['version'].presence,
              'release_date' => front_matter['release_date'].presence&.to_s }
    )
  end

  # The front matter carries what the Help Center stores in columns and in `meta`; everything after it is the article.
  def split(source)
    match = source.match(FRONT_MATTER)
    raise ArgumentError, 'A documentation article needs YAML front matter' if match.nil?

    [YAML.safe_load(match[1], permitted_classes: [Date]), match.post_match.strip]
  end
end
