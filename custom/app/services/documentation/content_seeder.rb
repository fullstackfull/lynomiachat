# Lynomia global documentation: seeds the documentation corpus from source control into the platform portal.
#
# One-time, operator-run, idempotent: `rails documentation:content`. Not a scraper and not a background job -- the
# content lives in this repository as Markdown with YAML front matter, is reviewed the way code is reviewed, and is
# upserted by slug so re-running it updates rather than duplicates.
#
# TWO PHASES, AND NO WRAPPING TRANSACTION (owner ruling 3; P2-SOURCE-OF-TRUTH-CONTRACT.md D9):
#
#   PREFLIGHT  Reads the manifest, every corpus file and every row this run would touch, and WRITES NOTHING.
#              It parses the corpus, validates the required fields, validates identity and provenance, detects the
#              conflicts a one-file-at-a-time pass cannot see -- two files claiming one globally unique slug, a
#              slug another row already holds -- validates every `media:` reference, and classifies every tracked
#              row. On any failure it raises PreflightError naming EVERY offending file, before the first write.
#   APPLY      Deterministic and idempotent: manifest order, default locale first, file-name order, one upsert per
#              file keyed on (slug, locale). A failure here raises ApplyFailure carrying the counts of everything
#              that completed plus the file that failed. Nothing after it is attempted, nothing is rolled back,
#              and the task is rerunnable because every write is an upsert on that key.
#
# There is deliberately NO transaction around either phase. Media attachments and their files live outside any
# database transaction, so a wrapping transaction would look like an atomicity boundary without being one; and
# because everything decidable before a write is decided in the preflight, it would buy nothing in exchange for
# holding a lock window against `increment_view_count`, which is a live unauthenticated public writer (D9).
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
  MERGEABLE_COLUMNS = %w[title description position].freeze
  MERGEABLE_META_KEYS = %w[title description tags version release_date].freeze
  MERGEABLE_FIELDS = (MERGEABLE_COLUMNS + MERGEABLE_META_KEYS.map { |key| "meta.#{key}" }).freeze

  # First element of every digest payload. Changing what a digest covers has to invalidate every stored digest, and
  # that turns the whole corpus untracked on the next run -- a loud, operator-gated event rather than a silent
  # reclassification. NEVER change the payload without bumping this.
  DIGEST_VERSION = 1

  # Both failures are nested here rather than added to lib/custom_exceptions/ for the reason
  # R2-MEDIA-INTERFACE.md section 3.5 gives for Documentation::MediaSeeder::Error: they are service-local
  # failures an operator reads out of a rake task, not application-wide exceptions a controller rescues.

  # The corpus will not apply cleanly. Carries one line per offending file, and NOTHING has been written.
  class PreflightError < StandardError; end

  # A write failed. Carries the file it failed on and the counts of everything that completed before it, because
  # the ruling's "report exactly what completed and what failed" is only answerable with both.
  class ApplyFailure < StandardError
    attr_reader :where, :result

    def initialize(where:, cause:, result:)
      @where = where
      @result = result
      super("#{where}: #{cause.class.name}: #{cause.message}")
    end
  end

  # created/updated/unchanged/adopted/untracked are mutually exclusive outcomes, one per file processed, so they
  # reconcile against the corpus. `divergences` is the per-field detail behind them.
  Result = Struct.new(:created, :updated, :unchanged, :adopted, :untracked, :locales, :divergences,
                      keyword_init: true)
  Divergence = Struct.new(:kind, :locale, :slug, :path, :fields, keyword_init: true)

  # THE CORPUS ON DISK, parsed once: the manifest, the locale trees, and every property that is decidable from the
  # files themselves. It holds no portal, runs no query and writes nothing, which is half of why the preflight can
  # promise it writes nothing -- the other half is that the row side only ever reads.
  #
  # Nested rather than put in a second file: it is private to this one, its only caller is the class around it, and
  # Zeitwerk resolves it from here. The cop's allowlist (rubocop/one_class_per_file.rb:76-83) enumerates name
  # suffixes rather than nesting, so the alternative is a class named to satisfy a linter.
  class Corpus # rubocop:disable Style/OneClassPerFile
    FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n/m

    # One manifest section in one locale, with the files that belong to it, flattened in APPLY ORDER: manifest
    # section order, default locale first, file name order. The raw manifest hash does not leave this class.
    Section = Struct.new(:slug, :locale, :name, :description, :position, :icon, :files, keyword_init: true)

    # One corpus file, parsed. `columns` and `meta` hold only the class-C fields, which is what keeps the merge and
    # the digests reading from the same two hashes instead of from two shapes that can drift apart. `slug` is the
    # public address this file claims: the file name is the article's stable KEY -- what a product link in the
    # dashboard points at -- and every locale but the default suffixes it.
    FileState = Struct.new(:locale, :slug, :body, :doc_key, :source_path, :columns, :meta, keyword_init: true) do
      def default_locale? = locale == Documentation::Library::DEFAULT_LOCALE
    end

    def initialize(root:, locales:)
      @root = root
      @locales = locales
      @unparsed = []
    end

    def sections
      @sections ||= manifest.fetch('sections').flat_map do |section|
        locales.filter_map { |locale| build_section(section, locale) }
      end
    end

    # Refused before the walk, because a section with no `slug` has no directory to glob and a section with no
    # `name` cannot produce a category: the manifest has to be sound before anything derived from it means
    # anything. Set equality against the directories on disk, per locale and in both directions, is here for the
    # same reason -- it is a statement about the manifest, not about any one file.
    def manifest_problems
      sections_data = manifest.fetch('sections')
      problems = sections_data.flat_map { |section| section_problems(section) }
      return problems if problems.any?

      locales.flat_map { |locale| parity_problems(sections_data, locale) }
    end

    # Everything else the corpus can decide on its own, in one list so an operator fixes a corpus once rather than
    # once per run: files that do not parse, missing required fields, broken media references, and the two
    # identity collisions that only a set comparison can see.
    def problems
      files = sections.flat_map(&:files)
      @unparsed + files.flat_map { |file| file_problems(file) } + slug_problems(files)
    end

    private

    attr_reader :root, :locales

    def manifest
      @manifest ||= YAML.load_file(root.join('manifest.yml'))
    end

    def build_section(section, locale)
      return unless section[locale]

      Section.new(slug: section['slug'], locale: locale, name: section[locale]['name'], position: section['position'],
                  description: section[locale]['description'], icon: section['icon'].to_s,
                  files: parse_files(section['slug'], locale))
    end

    # `Dir.glob` sorts, so the file order is the framework's guarantee rather than this file's.
    def parse_files(slug, locale)
      Dir.glob(root.join(locale, slug, '*.md')).filter_map { |path| parse(path, locale) }
    end

    # D9 mode 4: a YAML shape `safe_load` refuses -- `release_date: 2026-01-01 10:00:00` is a Time -- or malformed
    # YAML, or no front matter at all. The file is dropped from the plan so the cross-file checks still run over
    # the rest, and the run is already failing.
    def parse(path, locale)
      read_file(path, locale)
    rescue StandardError => e
      @unparsed << "#{relative(path)}: #{e.class.name}: #{e.message}"
      nil
    end

    def section_problems(section)
      slug = section['slug']
      problems = []
      problems << "manifest.yml: a section has no `slug`: #{section.inspect}" if slug.blank?
      problems << "manifest.yml section #{slug}: `position` must be an Integer, and is #{section['position'].inspect}" \
        unless section['position'].is_a?(Integer)
      problems + locales.filter_map do |locale|
        next if section[locale].nil? || section[locale]['name'].present?

        "manifest.yml section #{slug}: the #{locale} entry has no `name`, which is the category's one required field"
      end
    end

    # The directory direction is D9's mode 5: `perform!` iterates the MANIFEST, so a section directory the manifest
    # does not claim is silently never seeded -- no error, no warning, no count. The manifest direction is the
    # inverse, and publishes an empty category. Scoped to the locales the portal allows, so narrowing
    # `allowed_locales` keeps working: the corpus legitimately carries a locale tree the portal does not serve.
    def parity_problems(sections_data, locale)
      claimed = sections_data.select { |section| section[locale] }.pluck('slug')
      present = Dir.glob(root.join(locale, '*')).select { |path| File.directory?(path) }.map { |path| File.basename(path) }
      (present - claimed).map do |slug|
        "#{locale}/#{slug}: a corpus directory no manifest.yml section claims for #{locale}. Nothing in it is seeded"
      end + (claimed - present).map do |slug|
        "manifest.yml section #{slug}: there is no #{locale}/#{slug} directory, so the #{locale} category would be empty"
      end
    end

    def file_problems(file)
      problems = []
      problems << "#{file.source_path}: the front matter has no `title`" if file.columns['title'].blank?
      problems << "#{file.source_path}: `position` must be an Integer, and is #{file.columns['position'].inspect}" \
        unless file.columns['position'].is_a?(Integer)
      # D9 mode 1: `validates :content, presence: true, if: :published?` (app/models/article.rb:69) refuses the row
      # the moment it is published, and an article with no prose is a corpus defect whatever its status.
      problems << "#{file.source_path}: the file has front matter and no body" if file.body.blank?
      problems + media_problems(file)
    end

    # IDENTITY, the half no single file can answer. `articles.slug` is GLOBALLY unique
    # (db/schema.rb index_articles_on_slug) while the lookup is `(slug, locale)`, so two files can derive one slug
    # and neither the lookup nor the portal scope can see it:
    #
    #   F7  an `en` file named foo-ar.md and an `ar` file named foo.md both derive `foo-ar`. Measured on the
    #       shipped seeder: the second INSERT raises RecordNotUnique with three rows and two categories committed.
    #   F8  two files with one basename in two sections derive one (slug, locale), so the second file UPDATES the
    #       row the first created. Measured: `1 created, 1 updated` for two files, the later section wins, and the
    #       first file's prose is never published. Nothing raises, which is why only a set comparison catches it.
    #
    # `RESERVED_SLUGS` is here too because it is locale-asymmetric: `search.md` fails for `en` (D9 mode 2) and
    # seeds fine as `search-ar`, so the file name alone does not say whether it is legal.
    def slug_problems(files)
      reserved = files.select { |file| Article::RESERVED_SLUGS.include?(file.slug) }.map do |file|
        "#{file.source_path}: #{file.slug.inspect} is a reserved slug (Article::RESERVED_SLUGS)"
      end
      reserved + files.group_by(&:slug).select { |_slug, claimants| claimants.size > 1 }.map do |slug, claimants|
        "#{slug.inspect} is the slug of #{claimants.map(&:source_path).join(' and ')}: articles.slug is globally " \
          'unique, so these files cannot both be seeded'
      end
    end

    # "Validate media references" (owner ruling 3A), for the one media fact this seeder can establish on its own: a
    # `media:` key with no file behind it. R2-MEDIA-INTERFACE.md section 1.4 -- the resolver answers nil at render
    # time, so the page publishes the fallback and nothing says so. The grammar and the media directory name are
    # read from the classes that own them (interface section 1.5: one rule, one place), never copied.
    #
    # Parsed, not scanned: an image node is the only thing the renderer resolves, so a `media:` key inside a code
    # fence -- which is how the grammar itself gets documented -- is correctly not a reference.
    def media_problems(file)
      media_keys(file.body).filter_map do |key|
        unless Documentation::MediaResolver.valid_key?(key)
          next "#{file.source_path}: media:#{key} is not a valid media key (R2-MEDIA-INTERFACE.md section 1.2)"
        end

        path = root.join(Documentation::MediaSeeder::MEDIA_DIR, key)
        next if path.file?

        "#{file.source_path}: media:#{key} has no file at #{path.relative_path_from(Rails.root)}"
      end
    end

    def media_keys(body)
      CommonMarker.render_doc(body, :DEFAULT, [:table]).walk.filter_map do |node|
        next unless node.type == :image && node.url.to_s.start_with?(Documentation::MediaResolver::SCHEME)

        node.url.to_s.delete_prefix(Documentation::MediaResolver::SCHEME)
      end
    end

    # Nothing here raises for a missing field: the preflight reports every one of them against its file, so a
    # `fetch` would abort the walk and hide the rest of the list.
    def read_file(path, locale)
      front_matter, body = split(File.read(path))
      key = File.basename(path, '.md')
      FileState.new(
        locale: locale, body: body, doc_key: key, source_path: relative(path),
        slug: locale == Documentation::Library::DEFAULT_LOCALE ? key : "#{key}-#{locale}",
        columns: { 'title' => front_matter['title'], 'description' => front_matter['description'],
                   'position' => front_matter['position'] },
        meta: { 'title' => front_matter['seo_title'].presence || front_matter['title'],
                'description' => front_matter['seo_description'].presence || front_matter['description'],
                'tags' => Array(front_matter['tags']), 'version' => front_matter['version'].presence,
                'release_date' => front_matter['release_date'].presence&.to_s }
      )
    end

    # The front matter carries what the Help Center stores in columns and in `meta`; everything after it is the
    # article.
    def split(source)
      match = source.match(FRONT_MATTER)
      raise ArgumentError, 'A documentation article needs YAML front matter' if match.nil?

      [YAML.safe_load(match[1], permitted_classes: [Date]), match.post_match.strip]
    end

    def relative(path)
      Pathname.new(path).relative_path_from(Rails.root).to_s
    end
  end

  # What the preflight decided about one corpus file, and the only thing the apply phase reads.
  #
  # `kept` is the class-C fields the operator owns and this run must not write. `taken` is the opposite and exists
  # only while adopting: the class-C fields whose stored value the corpus is about to overwrite, which is what an
  # `ADOPT_UNTRACKED` run has to report (P2-WORKSTREAM-OWNERSHIP.md A6-O1).
  PlannedFile = Struct.new(:file, :article, :kept, :taken, :adopting, keyword_init: true)

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

  # Set before the preflight runs, so an ApplyFailure's partial result still names the locales it was seeding.
  def perform!
    @result.locales = locales
    apply!(preflight!)
    @result
  end

  private

  attr_reader :portal, :author, :root

  # The default locale is seeded first, because every other locale links its translation to that article.
  def locales
    @locales ||= (Documentation::Library::LOCALES & portal.allowed_locale_codes)
                 .sort_by { |locale| locale == Documentation::Library::DEFAULT_LOCALE ? 0 : 1 }
  end

  def corpus
    @corpus ||= Corpus.new(root: root, locales: locales)
  end

  # PHASE 1 -- THE PREFLIGHT. Not one write, and that is the property the whole failure model rests on: the run can
  # say "this corpus will not apply cleanly" with the database exactly as it found it.
  #
  # Every problem is collected rather than raised on sight, because an operator fixing a corpus wants the whole
  # list and not the alphabetically first line of it. The manifest is the one thing refused on its own: nothing
  # derived from an unsound manifest -- not a glob, not a category -- means anything.
  def preflight!
    refuse(corpus.manifest_problems)
    plan = corpus.sections.index_with { |section| section.files.map { |file| plan_file(file) } }
    refuse(corpus.problems + foreign_row_problems(plan))
    plan
  end

  def refuse(problems)
    raise PreflightError, problems.join("\n") if problems.any?
  end

  # PROVENANCE: the three-way class of every row, decided BEFORE anything is written (D9 phase 1 item 5). The
  # lookup stays `(slug, locale)` -- `slug` left ArticleDashboard::FORM_ATTRIBUTES in wave 2 and no live path
  # writes it on an existing row, so it is as stable an identity as the provenance column would be (D4).
  def plan_file(file)
    article = portal.articles.find_or_initialize_by(slug: file.slug, locale: file.locale)
    adopting = article.persisted? && article.seeded_digests.blank?
    PlannedFile.new(file: file, article: article, adopting: adopting,
                    kept: article.new_record? || adopting ? [] : operator_fields(article, file),
                    taken: adopting ? reclaimed_fields(article, file) : [])
  end

  # The same global index from the row side: another portal's row, or this portal's row in another locale, already
  # holding a slug this run intends to write. Measured as RecordNotUnique on the second of the two seed tasks when
  # a docs file and a changelog file share a name (D9 mode 3), and it is also the transient collision D4 names,
  # where an operator-renamed slug sits on another row's address.
  def foreign_row_problems(plan)
    files = plan.values.flatten
    owned = files.filter_map { |planned| planned.article.id }
    by_slug = files.group_by { |planned| planned.file.slug }
    Article.where(slug: by_slug.keys).where.not(id: owned).includes(:portal).map do |row|
      "#{by_slug[row.slug].first.file.source_path}: slug #{row.slug.inspect} is already article ##{row.id} " \
        "(portal #{row.portal.slug}, locale #{row.locale}), and articles.slug is globally unique"
    end
  end

  # PHASE 2 -- THE APPLY. One rescue, around the whole phase: `where` is the unit the run had reached, so the
  # failure names the corpus file an operator has to open, and `@result` carries what completed up to it.
  def apply!(plan)
    where = nil
    plan.each do |section, planned_files|
      where = "manifest.yml section #{section.slug} (#{section.locale})"
      category = upsert_category(section)
      planned_files.each do |planned|
        where = planned.file.source_path
        apply_file(planned, category)
      end
    end
  rescue StandardError => e
    raise ApplyFailure.new(where: where, cause: e, result: @result)
  end

  def upsert_category(section)
    category = portal.categories.find_or_initialize_by(slug: section.slug, locale: section.locale)
    category.assign_attributes(name: section.name, description: section.description,
                               position: section.position, icon: section.icon)
    category.save!
    category
  end

  # A row the seeder has never tracked: `seeded_digests` is empty, so there is no way to tell a previous seed's own
  # writing from an operator's. Writing it would be exactly the silent overwrite this design exists to prevent, so
  # the run reports it and leaves it, and `ADOPT_UNTRACKED=1` is the operator saying once, by hand, that the corpus
  # wins (P2-SOURCE-OF-TRUTH-CONTRACT.md D7).
  def apply_file(planned, category)
    return record_untracked(planned.file) if planned.adopting && !@adopt_untracked

    record(planned, write(planned, category))
  end

  # Returns true when the row was written.
  def write(planned, category)
    article = planned.article
    assign(article, planned, category)
    changed = article.changed?
    intended_position = article.position
    article.save!
    converge_position(article, intended_position)
    changed
  end

  # Everything the seeder is allowed to write, in one place and in class order: A, then B on create only, then C
  # for the fields the operator has not taken over, then the digests of what this run wrote.
  def assign(article, planned, category)
    file = planned.file
    article.assign_attributes(content: file.body, category: category, content_source_path: file.source_path)
    article.associated_article_id = root_article_id(file.doc_key) unless file.default_locale?
    article.status = @publish ? :published : :draft if article.new_record?
    MERGEABLE_COLUMNS.each { |column| article[column] = file.columns[column] unless planned.kept.include?(column) }
    article.meta = merged_meta(article, planned)
    article.seeded_digests = digests_for(article, planned)
    article.author ||= author
  end

  # Translations hang off the default-locale article, which is how the Help Center already links them.
  def root_article_id(key)
    portal.articles.find_by(slug: key, locale: Documentation::Library::DEFAULT_LOCALE)&.id
  end

  # `doc_key` is class D: the corpus owns it and reasserts it, because it is the identity every contextual-help link
  # resolves through (custom/app/services/documentation/library.rb:63). Every other key on the column belongs to
  # whoever last wrote it -- `feature_image` is the form's alone -- so the hash is merged key by key and never
  # replaced, which is the same rule ArticleMetaField.merge_submitted applies from the other side.
  def merged_meta(article, planned)
    meta = article.meta.to_h
    meta['doc_key'] = planned.file.doc_key
    MERGEABLE_META_KEYS.each do |key|
      next if planned.kept.include?("meta.#{key}")

      if planned.file.meta[key].nil?
        meta.delete(key)
      else
        meta[key] = planned.file.meta[key]
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

  # The other side of `operator_fields`, for an untracked row the operator has told the seeder to adopt: the
  # class-C fields whose stored value the corpus is about to replace. Class A is left out deliberately -- the
  # corpus owns prose and placement on every run for every row, so reporting it here would report the design
  # rather than the consequence of adopting.
  def reclaimed_fields(article, file)
    MERGEABLE_FIELDS.reject do |field|
      digest(field, current_value(article, field)) == digest(field, file_value(file, field))
    end
  end

  def digests_for(article, planned)
    MERGEABLE_FIELDS.index_with do |field|
      planned.kept.include?(field) ? article.seeded_digests[field] : digest(field, file_value(planned.file, field))
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
  # (app/models/article.rb:77,277-287) -- which is exactly what a corpus file moving between manifest sections
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

  # `operator_edited` is what the run left alone; `adopted` is what it took back. Both are per article and per
  # field, because "N adopted" with no field list is exactly the silent continuation the ruling forbids.
  def record(planned, changed)
    @result.divergences << divergence(:operator_edited, planned.file, planned.kept) if planned.kept.any?
    @result.divergences << divergence(:adopted, planned.file, planned.taken) if planned.adopting && planned.taken.any?
    @result[outcome(planned, changed)] += 1
  end

  # One outcome per file processed, so created + updated + unchanged + adopted + untracked reconciles against the
  # corpus on disk. A row can be `updated` and carry a divergence in the same run: class A is written while a
  # class-C field the operator owns is left alone.
  def outcome(planned, changed)
    return :created if planned.article.previously_new_record?
    return :adopted if planned.adopting

    changed ? :updated : :unchanged
  end

  def record_untracked(file)
    @result.divergences << divergence(:untracked, file, [])
    @result.untracked += 1
  end

  def divergence(kind, file, fields)
    Divergence.new(kind: kind, locale: file.locale, slug: file.slug, path: file.source_path, fields: fields)
  end
end
