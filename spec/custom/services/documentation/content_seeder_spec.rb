require 'rails_helper'

# The seeder is operator-run and upsert-only: `rails documentation:content` can be run again at any time, and must
# update rather than duplicate. That property is the whole reason the corpus lives in source control, and until now
# nothing asserted it -- the corpus spec reads the files but never runs the seeder.
#
# These examples seed a temporary corpus rather than the shipped one, so they assert the seeder's behaviour instead
# of restating the contents of custom/db/documentation.
describe Documentation::ContentSeeder do
  let!(:super_admin) { create(:super_admin) }
  let!(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil,
                    config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let(:root) { Pathname.new(Dir.mktmpdir) }
  # Real PNG bytes with real dimensions, the same two fixtures media_seeder_spec.rb uses: 4x3 and 6x2. They have
  # to be real, because `MediaUpload#attach!` identifies the content type FROM THE BYTES -- a placeholder string
  # satisfies the preflight's file-existence check and is then refused by the attach boundary.
  let(:png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAAAAACRn/EaAAAAC0lEQVR4nGNgQAEAAA8AAbVWKT4AAAAASUVORK5CYII=') }
  let(:other_png) { Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAYAAAACCAAAAABeNvKCAAAAC0lEQVR4nGNgQAYAAA4AAamRc7EAAAAASUVORK5CYII=') }

  before do
    root.join('manifest.yml').write(<<~YAML)
      sections:
        - slug: getting-started
          position: 10
          icon: rocket
          en:
            name: Getting started
            description: The first thing to do.
          ar:
            name: البداية
            description: أول ما تفعله.
    YAML
    %w[en ar].each { |locale| FileUtils.mkdir_p(root.join(locale, 'getting-started')) }
    write('en', 'welcome', { title: 'Welcome', body: 'Start here.' })
    write('ar', 'welcome', { title: 'مرحباً', body: 'ابدأ من هنا.' })
  end

  after { FileUtils.remove_entry(root) }

  def write(locale, key, front_matter)
    front = { 'description' => "#{front_matter[:title]} description", 'position' => 10,
              'tags' => %w[getting-started] }.merge(front_matter.except(:body).transform_keys(&:to_s)).compact
    body = front_matter[:body]
    root.join(locale, 'getting-started', "#{key}.md").write("---\n#{front.to_yaml.delete_prefix("---\n")}---\n#{body}\n")
  end

  def seed(**overrides) = described_class.new(portal: portal, root: root, **overrides).perform!

  # The second half of what a corpus is: bytes at a path under media/, which is a sibling of the locale trees and
  # locale-independent, so the EN and AR translations of a page reference one file.
  def media(key, bytes = png)
    path = root.join('media', key)
    FileUtils.mkdir_p(path.dirname)
    path.binwrite(bytes)
  end

  def attached_keys
    portal.reload.documentation_media.map { |attachment| attachment.blob.metadata['documentation_key'] }
  end

  it 'creates one article per locale on the first run' do
    result = seed

    expect(result.created).to eq(2)
    expect(result.updated).to eq(0)
    expect(portal.reload.articles.count).to eq(2)
  end

  # The property that makes it safe to run on every deploy.
  it 'changes nothing when run again' do
    seed
    second = seed
    third = seed

    expect([second.created, second.updated, second.unchanged]).to eq([0, 0, 2])
    expect([third.created, third.updated, third.unchanged]).to eq([0, 0, 2])
    expect(portal.reload.articles.count).to eq(2)
  end

  it 'updates an article whose file changed, rather than adding a second one' do
    seed
    write('en', 'welcome', { title: 'Welcome', body: 'Start somewhere else.' })

    result = seed

    expect([result.created, result.updated]).to eq([0, 1])
    expect(portal.reload.articles.find_by(locale: 'en').content).to eq('Start somewhere else.')
    expect(portal.articles.count).to eq(2)
  end

  it 'adds a new file without touching the others' do
    seed
    write('en', 'second', { title: 'Second', body: 'More.', position: 20 })
    write('ar', 'second', { title: 'الثاني', body: 'المزيد.', position: 20 })

    result = seed

    expect([result.created, result.updated, result.unchanged]).to eq([2, 0, 2])
  end

  describe 'what it writes' do
    before { seed }

    # The file name is the stable key: it is what a product link points at, and the slug is derived from it so the
    # two locales can both exist under a globally unique slug.
    it 'derives the slug from the file name, and suffixes every locale but the default' do
      expect(portal.reload.articles.pluck(:slug).sort).to eq(%w[welcome welcome-ar])
    end

    it 'stores the key in meta, which is what the key-to-locale lookup reads' do
      expect(portal.reload.articles.pluck(Arel.sql("meta->>'doc_key'")).uniq).to eq(['welcome'])
    end

    it 'links the translation to the default-locale article' do
      english = portal.reload.articles.find_by(locale: 'en')
      arabic = portal.articles.find_by(locale: 'ar')

      expect(arabic.associated_article_id).to eq(english.id)
      expect(english.associated_article_id).to be_nil
    end

    it 'creates the category in every locale, at the manifest position' do
      categories = portal.reload.categories.where(slug: 'getting-started')

      expect(categories.pluck(:locale).sort).to eq(%w[ar en])
      expect(categories.pluck(:position).uniq).to eq([10])
      expect(categories.find_by(locale: 'ar').name).to eq('البداية')
    end

    it 'publishes, and attributes the article to a super admin' do
      expect(portal.reload.articles.pluck(:status).uniq).to eq(['published'])
      expect(portal.articles.pluck(:author_id).uniq).to eq([super_admin.id])
    end

    it 'falls back to the description for SEO when no seo_description is given' do
      expect(portal.reload.articles.find_by(locale: 'en').meta['description']).to eq('Welcome description')
    end
  end

  it 'prefers an explicit seo_description over the description' do
    write('en', 'welcome', { title: 'Welcome', body: 'Start here.', seo_description: 'For a search engine' })
    seed

    expect(portal.reload.articles.find_by(locale: 'en').meta['description']).to eq('For a search engine')
  end

  it 'can seed drafts, so a corpus can be reviewed before it is published' do
    seed(publish: false)

    expect(portal.reload.articles.pluck(:status).uniq).to eq(['draft'])
  end

  # A file without front matter has no title and no position, so there is nothing to seed. Failing loudly is the
  # point: a silent skip would ship a corpus with a hole in it. Both of these were an ArgumentError and a KeyError
  # raised mid-walk with the earlier files already written; they are now preflight refusals that write nothing.
  it 'refuses a file with no front matter' do
    root.join('en', 'getting-started', 'broken.md').write("Just a body.\n")

    expect { seed }.to raise_error(described_class::PreflightError, /broken\.md.*front matter/)
  end

  it 'refuses a file whose front matter has no title' do
    root.join('en', 'getting-started', 'broken.md').write("---\nposition: 20\n---\nBody.\n")

    expect { seed }.to raise_error(described_class::PreflightError, /broken\.md: the front matter has no `title`/)
  end

  it 'seeds only the locales the portal allows' do
    portal.update!(config: portal.config.merge('allowed_locales' => ['en']))

    expect(seed.created).to eq(1)
    expect(portal.reload.articles.pluck(:locale)).to eq(['en'])
  end

  it 'requires a super admin to attribute the content to' do
    SuperAdmin.delete_all

    expect { described_class.new(portal: portal, root: root).perform! }.to raise_error(ArgumentError, /super admin/)
  end

  # THE FIELD-BY-FIELD SOURCE OF TRUTH (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md section 2). Nine
  # fields have two writers -- this seeder and ArticleDashboard::FORM_ATTRIBUTES -- and a deploy must never
  # silently revert the operator's. Each class is asserted through the seeder, from an edited row.
  describe 'what a deploy may overwrite' do
    let(:english) { portal.reload.articles.find_by(locale: 'en') }

    before { seed }

    it 'records the corpus file that owns the row, and the file name as the contextual-help key' do
      expect(english.content_source_path).to eq(Pathname.new(root.join('en', 'getting-started', 'welcome.md'))
                                                       .relative_path_from(Rails.root).to_s)
      expect(english.meta['doc_key']).to eq('welcome')
    end

    # Class A. The corpus is the source of truth for prose and placement, so the seeder wins.
    it 'reverts an edited body, because content is repository-owned' do
      english.update!(content: 'Operator body.')

      expect(seed.updated).to eq(1)
      expect(english.reload.content).to eq('Start here.')
    end

    # Class B. The file does not express `status`; the seeder forces it from its own publish flag, so before this
    # change a deploy republished an article the operator had deliberately withdrawn.
    it 'leaves an unpublished article unpublished' do
      english.update!(status: :draft)

      expect(seed.updated).to eq(0)
      expect(english.reload.status).to eq('draft')
    end

    # Class C, the whole point: written only while the row still holds what the seeder last wrote there.
    it 'overwrites a title the operator has not touched' do
      write('en', 'welcome', { title: 'Welcome, renamed', body: 'Start here.' })

      expect(seed.updated).to eq(1)
      expect(english.reload.title).to eq('Welcome, renamed')
    end

    it 'keeps an operator-edited title, and reports it per field' do
      english.update!(title: 'Operator title')
      write('en', 'welcome', { title: 'Corpus title', body: 'Start here.' })

      result = seed

      expect(english.reload.title).to eq('Operator title')
      divergence = result.divergences.sole
      expect([divergence.kind, divergence.locale, divergence.slug]).to eq([:operator_edited, 'en', 'welcome'])
      expect(divergence.fields).to eq(%w[title])
      expect(divergence.path).to eq(english.content_source_path)
    end

    # Each class-C field is decided on its own: an edited title does not freeze the SEO description beside it.
    it 'keeps the edited field and still updates its neighbours' do
      english.update!(title: 'Operator title')
      write('en', 'welcome', { title: 'Corpus title', body: 'Start here.', seo_description: 'For a search engine' })

      seed

      expect(english.reload.title).to eq('Operator title')
      expect(english.meta['description']).to eq('For a search engine')
    end

    # Convergence: an operator and the corpus can arrive at the same text independently, and then there is no
    # divergence left to report. Without this the row would be reported as edited for ever.
    it 'reattaches a field whose edit the corpus has caught up with' do
      english.update!(title: 'Agreed title')
      write('en', 'welcome', { title: 'Agreed title', body: 'Start here.' })

      expect(seed.divergences).to be_empty
      expect(seed.unchanged).to eq(2)
    end

    # Class D, and the hard prerequisite from P2-WORKSTREAM-OWNERSHIP.md E1: the seeder used to repair a destroyed
    # `doc_key` by accident, by replacing the whole jsonb. It no longer replaces it, so the key has to survive the
    # edit on the other side AND be reasserted here. Both halves are checked.
    it 'keeps doc_key, and the operator-owned meta keys, across a seed after an edit' do
      english.update!(meta: english.meta.merge('feature_image' => 'https://example.test/og.png'))

      seed

      expect(english.reload.meta['doc_key']).to eq('welcome')
      expect(english.meta['feature_image']).to eq('https://example.test/og.png')
      expect(Documentation::Library.article_for('welcome', locale: 'en')).to eq(english)
    end

    it 'reasserts doc_key on a row whose key was destroyed before wave 2 closed that path' do
      english.update!(meta: { 'title' => 'SEO' })

      seed

      expect(english.reload.meta['doc_key']).to eq('welcome')
    end
  end

  # A row the seeder has never tracked: every production row is in this state the moment the migration lands, and
  # nothing in the repository can tell a previous seed's own writing from an operator's edit.
  describe 'a row with no provenance' do
    let(:english) { portal.reload.articles.find_by(locale: 'en') }

    before do
      seed
      english.update!(seeded_digests: {}, content_source_path: nil, title: 'Operator title', status: :draft)
    end

    it 'writes nothing to it and reports it' do
      result = seed

      expect([result.untracked, result.updated, result.unchanged]).to eq([1, 0, 1])
      expect(result.divergences.sole.kind).to eq(:untracked)
      expect(english.reload.title).to eq('Operator title')
    end

    it 'applies the corpus to it once, by hand, under ADOPT_UNTRACKED' do
      result = seed(adopt_untracked: true)

      expect([result.adopted, result.untracked]).to eq([1, 0])
      expect(english.reload.title).to eq('Welcome')
      expect(english.content_source_path).to be_present
    end

    # Adoption is not creation: it reproduces the corpus, not the publish flag, so the withdrawal above stands.
    it 'does not republish it while adopting it' do
      seed(adopt_untracked: true)

      expect(english.reload.status).to eq('draft')
    end

    # P2-WORKSTREAM-OWNERSHIP.md A6-O1: the run printed `1 adopted` and no divergence line, so the operator never
    # learned WHICH fields the corpus took back -- the silent continuation the owner's point C forbids. Class A is
    # deliberately absent: the corpus owns prose on every run for every row, tracked or not.
    it 'reports which fields the adoption overwrote' do
      divergence = seed(adopt_untracked: true).divergences.sole

      expect([divergence.kind, divergence.locale, divergence.slug]).to eq([:adopted, 'en', 'welcome'])
      expect(divergence.fields).to eq(%w[title])
    end
  end

  # THE SECTION MOVE, which the integrator's no-op probe could not exercise and which is the one content-level
  # non-convergence source (P2-WORKSTREAM-OWNERSHIP.md E2 point 1). `Article` re-derives `position` as `max + 10`
  # in an after_save when `category_id` changes, which discards the authored order; measured before the fix, the
  # moved article held 20 after one run and the front-matter 10 only came back on a second.
  describe 'a file that moves between manifest sections' do
    before do
      root.join('manifest.yml').write(<<~YAML)
        sections:
          - slug: getting-started
            position: 10
            icon: i-lucide-rocket
            en:
              name: Getting started
              description: The first thing to do.
          - slug: whatsapp
            position: 20
            icon: i-lucide-message-circle
            en:
              name: WhatsApp
              description: Connect WhatsApp.
      YAML
      FileUtils.mkdir_p(root.join('en', 'whatsapp'))
      root.join('en', 'whatsapp', 'connect.md').write("---\ntitle: Connect\nposition: 10\n---\nConnect it.\n")
      # This manifest claims neither section for `ar`, and the preflight refuses a locale tree no section claims,
      # so the fixture says what it means: these two examples are about the English move.
      FileUtils.rm_rf(root.join('ar'))
      seed
      FileUtils.mv(root.join('en', 'getting-started', 'welcome.md').to_s, root.join('en', 'whatsapp', 'welcome.md').to_s)
    end

    it 'keeps the authored position and converges in one run' do
      moved = seed
      again = seed

      article = portal.reload.articles.find_by(slug: 'welcome')
      expect(article.position).to eq(10)
      expect(article.category.slug).to eq('whatsapp')
      expect(moved.updated).to eq(1)
      expect([again.updated, again.unchanged]).to eq([0, 2])
    end

    it 'follows the file, rather than creating a second row for it' do
      seed

      expect(portal.reload.articles.where(slug: 'welcome').count).to eq(1)
      expect(portal.articles.find_by(slug: 'welcome').content_source_path).to end_with('en/whatsapp/welcome.md')
    end
  end

  # THE FAILURE MODEL (owner ruling 3; P2-SOURCE-OF-TRUTH-CONTRACT.md D9). Each defect below was measured on this
  # branch BEFORE the phase split, on a fixture corpus carrying exactly that shape:
  #
  #   F7  one slug from two locales       -> ActiveRecord::RecordNotUnique, 3 articles and 2 categories committed
  #   F8  one basename in two sections    -> `1 created, 1 updated` for two files; the later section won and the
  #                                          first file's prose was never published. NOTHING raised
  #   a front-matter-only stub            -> RecordInvalid, 1 row already written
  #   `search.md`                         -> RecordInvalid, 1 row already written
  #   `release_date: 2026-01-01 10:00:00` -> Psych::DisallowedClass, 1 row already written
  #   a directory the manifest omits      -> 2 files, 1 row, no error and no count
  #   a docs key equal to a changelog key -> RecordNotUnique on whichever of the two tasks ran second
  #   `media:` with no file               -> the article published with a broken reference; nothing checked it
  #
  # Every one of them is now refused before the first write.
  describe 'the preflight' do
    it 'refuses two files that derive one slug across locales (F7)' do
      write('en', 'welcome-ar', { title: 'Welcome AR', body: 'The trap: this file name is the Arabic slug.' })

      expect { seed }.to raise_error(described_class::PreflightError, %r{
        "welcome-ar"\sis\sthe\sslug\sof\s.*en/getting-started/welcome-ar\.md\sand\s.*ar/getting-started/welcome\.md
      }x)
      expect([portal.reload.articles.count, portal.categories.count]).to eq([0, 0])
    end

    # THE NO-WRITE PROOF, and it is a measurement rather than an assertion about intent: every INSERT, UPDATE and
    # DELETE this seeder's own connection issues is recorded, and the preflight is run against a corpus it must
    # refuse. The row counts are the second half, because a write that never reached SQL is not the only way to
    # change state -- an attachment would.
    it 'writes nothing at all while deciding that the corpus will not apply' do
      write('en', 'welcome-ar', { title: 'Welcome AR', body: 'The trap.' })
      statements = []
      recorder = ->(*args) { statements << args.last[:sql] if args.last[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }

      # A DELTA, NOT A GLOBAL COUNT. The claim is that the PREFLIGHT writes nothing, which is a statement about what
      # CHANGED -- so it is measured as what changed. Asserting these four counts were globally zero made this
      # example depend on every other spec sharing its process, and that is not a theoretical fragility: CI run
      # 39024646651 went red here on `got: [0, 0, 0, 1]`, an ActiveStorage::Blob left behind by an earlier file in
      # the same 16-way shard, with nothing wrong in this seeder at all. (The merge report had recorded that the
      # sharding could not put the leaking and asserting files in one process. It can: shard 15 holds 61 files and
      # this is the 15th of them, behind two that create blobs.)
      #
      # The delta form is also strictly STRONGER than what it replaces, because it still catches a write made
      # against a database that did not start empty -- which the global-zero form could not tell from a dirty start.
      before = [Article.count, Category.count, ActiveStorage::Attachment.count, ActiveStorage::Blob.count]

      ActiveSupport::Notifications.subscribed(recorder, 'sql.active_record') do
        expect { seed }.to raise_error(described_class::PreflightError)
      end

      expect(statements).to be_empty
      expect([Article.count, Category.count, ActiveStorage::Attachment.count, ActiveStorage::Blob.count])
        .to eq(before)
    end

    # Locale-asymmetric, which is why the file name alone cannot answer it: `search.md` is `search` in English and
    # `search-ar` in Arabic, and only the first is reserved.
    it 'refuses a file name that is a reserved slug, in the locale where it is one' do
      write('en', 'search', { title: 'Search', body: 'How to search.' })
      write('ar', 'search', { title: 'البحث', body: 'كيف تبحث.' })

      expect { seed }.to raise_error(described_class::PreflightError) do |error|
        expect(error.message).to include('en/getting-started/search.md: "search" is a reserved slug')
        expect(error.message).not_to include('ar/getting-started/search.md')
      end
    end

    it 'refuses a front-matter-only stub, which the model refuses only once the row is published' do
      root.join('en', 'getting-started', 'stub.md').write("---\ntitle: Stub\nposition: 20\n---\n")

      expect { seed }.to raise_error(described_class::PreflightError,
                                     %r{en/getting-started/stub\.md: the file has front matter and no body})
    end

    it 'refuses a YAML shape safe_load will not load' do
      root.join('en', 'getting-started', 'timed.md')
          .write("---\ntitle: Timed\nposition: 20\nrelease_date: 2026-01-01 10:00:00\n---\nBody.\n")

      expect { seed }.to raise_error(described_class::PreflightError, /timed\.md: Psych::DisallowedClass/)
    end

    it 'refuses a position that is not an Integer' do
      write('en', 'welcome', { title: 'Welcome', body: 'Start here.', position: 'first' })

      expect { seed }.to raise_error(described_class::PreflightError, /`position` must be an Integer, and is "first"/)
    end

    # The seeder iterates the MANIFEST, so before the preflight this directory was silently never seeded: no
    # error, no warning, and no count an operator could reconcile against the files on disk.
    it 'refuses a corpus directory no manifest section claims' do
      FileUtils.mkdir_p(root.join('en', 'orphan-section'))
      root.join('en', 'orphan-section', 'never-seeded.md').write("---\ntitle: Orphan\nposition: 10\n---\nLost.\n")

      expect { seed }.to raise_error(described_class::PreflightError,
                                     %r{en/orphan-section: a corpus directory no manifest\.yml section claims for en})
    end

    it 'refuses a manifest section with no directory, which would publish an empty category' do
      FileUtils.rm_rf(root.join('ar', 'getting-started'))

      expect { seed }.to raise_error(described_class::PreflightError,
                                     %r{section getting-started: there is no ar/getting-started directory})
    end

    it 'refuses a manifest locale entry with no name, instead of failing on the category write' do
      root.join('manifest.yml').write(<<~YAML)
        sections:
          - slug: getting-started
            position: 10
            icon: rocket
            en:
              name: Getting started
            ar:
              description: أول ما تفعله.
      YAML

      expect { seed }.to raise_error(described_class::PreflightError, /the ar entry has no `name`/)
    end

    # One run, the whole list: an operator fixing a corpus should not have to re-run the task per defect.
    it 'reports every offending file, not the first one' do
      write('en', 'untitled', { title: nil, body: 'Body.' })
      root.join('en', 'getting-started', 'stub.md').write("---\ntitle: Stub\nposition: 20\n---\n")

      expect { seed }.to raise_error(described_class::PreflightError) do |error|
        expect(error.message.lines.map(&:strip)).to contain_exactly(
          a_string_matching(%r{en/getting-started/stub\.md: the file has front matter and no body}),
          a_string_matching(%r{en/getting-started/untitled\.md: the front matter has no `title`})
        )
      end
    end

    # `articles.slug` is globally unique and `find_or_initialize_by` is portal-scoped, so this collision is
    # invisible to the lookup: before the preflight it was a raw PG::UniqueViolation from whichever of the two
    # seed tasks happened to run second.
    it 'refuses a slug a row in another portal already holds' do
      changelog = create(:portal, name: 'Lynomia Chat Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                                  platform_owned: true, account: nil,
                                  config: { 'allowed_locales' => ['en'], 'default_locale' => 'en' })
      create(:article, portal: changelog, account: nil, author: super_admin, slug: 'welcome', locale: 'en',
                       title: 'A release note', content: 'Shipped.')

      expect { seed }.to raise_error(described_class::PreflightError,
                                     /slug "welcome" is already article #\d+ \(portal lynomia-changelog, locale en\)/)
      expect(portal.reload.articles.count).to eq(0)
    end

    describe 'media references' do
      let(:body) { "Start here.\n\n![The inbox](media:getting-started/inbox.png)" }

      # OWNER TEST I: missing media fails in the PREFLIGHT, before the apply. The two extra assertions are what
      # make it a preflight proof rather than a message proof: no row and no attachment exists afterwards, so
      # nothing was written before the refusal.
      it 'refuses a key with no file in the corpus, before writing a row or an attachment' do
        write('en', 'welcome', { title: 'Welcome', body: body })

        expect { seed }.to raise_error(described_class::PreflightError,
                                       %r{media:getting-started/inbox\.png has no file at .*media/getting-started/inbox\.png})
        expect([portal.reload.articles.count, portal.documentation_media.count]).to eq([0, 0])
      end

      # The four defects `Corpus#media_problems` cannot see, which is why the media seeder's own write-free phase
      # runs in the preflight too -- `media_seeder.preflight!` at the end of `ContentSeeder#preflight!`, whose
      # method-level rescue re-raises its Error as a PreflightError. Each one is decidable with no write, so each
      # must refuse as a PreflightError and leave the database as the run found it. These four ARE the media
      # seeder's own guards: owner test I above is held by `Corpus#media_problems`, which predates this delta.

      {
        'empty alt text' => ['![](media:getting-started/inbox.png)', /has empty alt text/],
        'a key in a link position' => ['See [it](media:getting-started/inbox.png).', /used as a link destination/],
        'a destination CommonMark does not read as an image' => ['![Alt](media:getting-started/the inbox.png)',
                                                                 /contains a space/],
        'a corpus file in the reserved operator namespace' => ['![Alt](media:uploads/8f3a1c2b5d7e9a04-i.png)',
                                                               %r{reserved `uploads/` namespace}]
      }.each do |description, (reference, message)|
        it "refuses #{description} in the preflight, writing nothing" do
          media('getting-started/inbox.png')
          media('uploads/8f3a1c2b5d7e9a04-i.png')
          write('en', 'welcome', { title: 'Welcome', body: reference })

          expect { seed }.to raise_error(described_class::PreflightError, message)
          expect([portal.reload.articles.count, portal.documentation_media.count]).to eq([0, 0])
        end
      end

      # OWNER TEST A: the first seed ATTACHES the corpus image, as part of the same run that writes the rows.
      #
      # This example used to write the five bytes `'bytes'` to that path and assert `created == 2`, which was all
      # the preflight needed: it checks that a file EXISTS. Nothing read it, because nothing called the media
      # seeder (A5'-O1), so a placeholder passed. It is a real PNG now, and the assertions are about the
      # attachment rather than only the row count -- the key, the portal that owns it, and the provenance that
      # marks it corpus-owned.
      it 'attaches the corpus image to the portal, under its stable key and marked corpus-owned' do
        media('getting-started/inbox.png')
        write('en', 'welcome', { title: 'Welcome', body: body })

        result = seed

        expect([result.created, result.media.uploaded, result.media.replaced, result.media.unchanged]).to eq([2, 1, 0, 0])
        expect(attached_keys).to eq(['getting-started/inbox.png'])
        blob = portal.documentation_media.first.blob
        expect(blob.metadata['content_source_path'])
          .to eq(root.join('media/getting-started/inbox.png').relative_path_from(Rails.root).to_s)
        # Dimensions, so the renderer can emit width/height: a non-zero `unmeasured` would mean libvips is absent.
        expect([blob.metadata['width'], blob.metadata['height'], result.media.unmeasured]).to eq([4, 3, 0])
      end

      # OWNER TEST B: no media write on an identical re-seed. The blob id is the discriminator -- a count of
      # `unchanged` would also be printed by a run that re-uploaded identical bytes and then purged the old one.
      it 'writes no media on a second identical seed' do
        media('getting-started/inbox.png')
        write('en', 'welcome', { title: 'Welcome', body: body })
        seed
        first_blob_id = portal.reload.documentation_media.first.blob_id

        result = seed

        expect([result.media.uploaded, result.media.replaced, result.media.unchanged]).to eq([0, 0, 1])
        expect([portal.reload.documentation_media.count, portal.documentation_media.first.blob_id])
          .to eq([1, first_blob_id])
      end

      # OWNER TEST C: changed bytes update the SAME logical key. The key and the article's `media:` reference are
      # untouched, so a published page keeps working across the change -- that is the whole point of the key.
      it 'replaces the bytes of an existing key when the corpus file changes, keeping the key' do
        media('getting-started/inbox.png')
        write('en', 'welcome', { title: 'Welcome', body: body })
        seed
        first_blob_id = portal.reload.documentation_media.first.blob_id

        media('getting-started/inbox.png', other_png)
        result = seed

        expect([result.media.uploaded, result.media.replaced, result.media.unchanged]).to eq([0, 1, 0])
        expect(attached_keys).to eq(['getting-started/inbox.png'])
        expect(portal.reload.documentation_media.count).to eq(1)
        blob = portal.documentation_media.first.blob
        expect([blob.id == first_blob_id, blob.metadata['width'], blob.download.b]).to eq([false, 6, other_png])
      end

      # OWNER TEST E: an operator's upload survives a seed. It is in the reserved `uploads/` namespace and no
      # corpus file owns it, which is what the sweep reads -- but "survives" means the bytes are still served,
      # not merely that a row is still there.
      it 'leaves an operator upload attached, with its bytes, across a seed' do
        operator = Documentation::MediaUpload.new(portal: portal)
                                             .create!(io: StringIO.new(png), filename: 'pasted.png', alt: 'Alt')
        media('getting-started/inbox.png')
        write('en', 'welcome', { title: 'Welcome', body: body })

        result = seed

        expect(result.media.purged).to eq(0)
        expect(attached_keys).to contain_exactly(operator.key, 'getting-started/inbox.png')
        operator_blob = portal.documentation_media.find { |a| a.blob.metadata['documentation_key'] == operator.key }.blob
        expect([operator_blob.download.b, operator_blob.metadata.key?('content_source_path')]).to eq([png, false])
      end

      # OWNER TEST F: the orphan sweep purges corpus-owned media whose key has left the corpus, and CANNOT purge
      # operator media -- in the same run, so the example proves the sweep ran rather than that it did nothing.
      # `purge_later` deletes the attachment row synchronously and only enqueues the blob's own purge
      # (activestorage-7.2.3.2/app/models/active_storage/attachment.rb:60-66), so attachment presence is the
      # assertion even under the `:test` queue adapter.
      it 'purges the corpus orphan and never the operator upload, in one sweep' do
        operator = Documentation::MediaUpload.new(portal: portal)
                                             .create!(io: StringIO.new(png), filename: 'pasted.png', alt: 'Alt')
        media('getting-started/inbox.png')
        write('en', 'welcome', { title: 'Welcome', body: body })
        seed
        expect(attached_keys).to contain_exactly(operator.key, 'getting-started/inbox.png')

        write('en', 'welcome', { title: 'Welcome', body: 'No images any more.' })
        result = seed

        expect(result.media.purged).to eq(1)
        expect(attached_keys).to eq([operator.key])
      end

      # WHAT USED TO BE AN APPLY-TIME FAILURE AND IS NOW A PREFLIGHT ONE. This example first asserted that a
      # `.png` holding SVG bytes failed at the attach boundary with `result.media.uploaded == 1` -- one image
      # committed, then the raise. Agent 6 pointed out that the content type and the byte cap are decidable from
      # the file with no write, which made that the same defect the missing-file check was moved out of the write
      # loop to fix. So the preflight decides them now, and the property is the stronger one: NOTHING is written,
      # not even the first image.
      it 'refuses a file whose bytes are not a permitted raster type, before writing anything' do
        media('getting-started/inbox.png')
        media('getting-started/broken.png', '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>')
        write('en', 'welcome', { title: 'Welcome',
                                 body: "a\n\n![One](media:getting-started/inbox.png)\n\n![Two](media:getting-started/broken.png)" })

        expect { seed }.to raise_error(described_class::PreflightError, /not permitted/) do |error|
          # The location an operator opens: the corpus FILE and LINE that referred to it, plus the image path.
          expect(error.message).to match(%r{welcome\.md:\d+:.*media:getting-started/broken\.png})
        end
        expect([portal.reload.articles.count, portal.documentation_media.count]).to eq([0, 0])
      end

      it 'refuses a file over the byte cap in the preflight too' do
        media('getting-started/inbox.png', "\x89PNG\r\n\x1a\n#{'x' * (2.megabytes + 1)}")
        write('en', 'welcome', { title: 'Welcome', body: body })

        expect { seed }.to raise_error(described_class::PreflightError, /bytes; the cap is/)
        expect([portal.reload.articles.count, portal.documentation_media.count]).to eq([0, 0])
      end

      # OWNER REQUIREMENT 9, and ruling 3's requirement C one level down: a media write that fails after the
      # preflight passed must report what completed. Every DECIDABLE media defect is now refused before the
      # apply, so what is left is the undecidable kind -- the storage service refusing an object, a connection
      # lost mid-upload. That is what the stub stands in for; there is no corpus a fixture can hold that reaches
      # the attach boundary and fails there.
      #
      # Deterministic, and not by accident: both references are in ONE file, CommonMarker walks the AST in
      # document order, and `references[key] ||=` keeps first-reference insertion order, which `each_key` then
      # replays. So `broken.png` is reached after `inbox.png` and the partial count is 1. (`Dir.glob`'s sort is
      # what orders the FILES, which is a different guarantee and not the one this example rests on.)
      it 'reports the media work that completed when a later key fails at the attach boundary' do
        media('getting-started/inbox.png')
        media('getting-started/broken.png', other_png)
        write('en', 'welcome', { title: 'Welcome',
                                 body: "a\n\n![One](media:getting-started/inbox.png)\n\n![Two](media:getting-started/broken.png)" })
        # Stubbed at the STORAGE seam rather than at the service: `create_and_upload!` is where a real object
        # store refuses, and its `metadata` already carries the documentation key, so the failure can name one
        # image without the test knowing anything about the seeder's internals.
        allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_wrap_original do |original, **kwargs|
          key = kwargs.dig(:metadata, Documentation::MediaResolver::KEY_METADATA).to_s
          raise ActiveStorage::IntegrityError, 'the storage service refused the object' if key.include?('broken')

          original.call(**kwargs)
        end

        expect { seed }.to raise_error(described_class::ApplyFailure) do |error|
          # The live struct, assigned when the seeder was built, is what carries the count out.
          expect([error.where, error.result.media.uploaded]).to eq(['the corpus media pass', 1])
          expect(error.message).to include('the storage service refused the object')
          # The orphan sweep never ran, so its counters are nil rather than a zero that would claim it did.
          expect([error.result.media.purged, error.result.media.unreferenced]).to eq([nil, nil])
        end
        # The media pass is FIRST inside the apply, so no row was written: the corpus is exactly as it was.
        expect([portal.reload.articles.count, portal.categories.count]).to eq([0, 0])
        # And what completed really is committed, which is what makes the re-run an upsert rather than a repair.
        expect(attached_keys).to eq(['getting-started/inbox.png'])
      end

      # The other half of requirement 9, and the one the report makes a SPECIFIC promise about: APPLY_FAILED
      # tells the operator that "a re-run reapplies what completed as `unchanged`". That is a word, not a
      # sentiment, so it is pinned -- the key attached before the failure comes back as `unchanged` on the next
      # run rather than as a second upload or a replace.
      it 'reports the key that survived a failed run as unchanged on the next one' do
        media('getting-started/inbox.png')
        media('getting-started/broken.png', other_png)
        write('en', 'welcome', { title: 'Welcome',
                                 body: "a\n\n![One](media:getting-started/inbox.png)\n\n![Two](media:getting-started/broken.png)" })
        failing = true
        allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_wrap_original do |original, **kwargs|
          key = kwargs.dig(:metadata, Documentation::MediaResolver::KEY_METADATA).to_s
          raise ActiveStorage::IntegrityError, 'transient' if failing && key.include?('broken')

          original.call(**kwargs)
        end
        expect { seed }.to raise_error(described_class::ApplyFailure)

        failing = false
        result = seed

        expect([result.media.uploaded, result.media.replaced, result.media.unchanged]).to eq([1, 0, 1])
        expect(attached_keys).to contain_exactly('getting-started/inbox.png', 'getting-started/broken.png')
        expect(result.created).to eq(2)
      end

      it 'refuses a key the grammar rejects' do
        write('en', 'welcome', { title: 'Welcome', body: '![Passwords](media:../../etc/passwd)' })

        expect { seed }.to raise_error(described_class::PreflightError, /is not a valid media key/)
      end

      # The renderer resolves image nodes, so a key in a code fence is prose about the grammar and not a
      # reference. A regex over the raw bytes would refuse the corpus for documenting itself.
      it 'does not read a key inside a code fence as a reference' do
        write('en', 'welcome', { title: 'Welcome', body: "Like this:\n\n```\n![Alt](media:a/b.png)\n```" })

        expect(seed.created).to eq(2)
      end
    end

    describe 'two manifest sections claiming one file name' do
      before do
        root.join('manifest.yml').write(<<~YAML)
          sections:
            - slug: getting-started
              position: 10
              icon: rocket
              en:
                name: Getting started
                description: The first thing to do.
            - slug: whatsapp
              position: 20
              icon: message-circle
              en:
                name: WhatsApp
                description: Connect WhatsApp.
        YAML
        FileUtils.rm_rf(root.join('ar'))
        FileUtils.mkdir_p(root.join('en', 'whatsapp'))
        root.join('en', 'whatsapp', 'welcome.md')
            .write("---\ntitle: From section two\nposition: 10\n---\nProse of section two.\n")
      end

      # F8. Both files derive `(welcome, en)`, so the second UPDATED the row the first created: two files, one
      # row, `1 created, 1 updated`, and the first file's prose never published. The unique index on
      # content_source_path never fired, because there was only ever one row.
      it 'refuses them instead of collapsing both into one row (F8)' do
        expect { seed }.to raise_error(described_class::PreflightError, %r{
          "welcome"\sis\sthe\sslug\sof\s.*en/getting-started/welcome\.md\sand\s.*en/whatsapp/welcome\.md
        }x)
        expect(portal.reload.articles.count).to eq(0)
      end
    end
  end

  # The preflight is not omniscient, and this is the half of the owner's ruling that says what happens then: no
  # transaction, an honest report of what completed, and a task that is safe to run again. `position: 2147483648`
  # is an Integer -- so the preflight accepts it -- and out of range for an int4 column, so the write fails.
  # `zebra` sorts after `welcome`, which is what makes the failure mid-apply rather than on the first file.
  describe 'a failure during the apply phase' do
    before { write('en', 'zebra', { title: 'Zebra', body: 'Last.', position: 2_147_483_648 }) }

    it 'reports exactly what completed and what failed, and applies nothing after it' do
      expect { seed }.to raise_error(described_class::ApplyFailure) do |error|
        expect(error.where).to end_with('en/getting-started/zebra.md')
        expect(error.message).to include('en/getting-started/zebra.md', 'RangeError')
        expect([error.result.created, error.result.updated, error.result.unchanged]).to eq([1, 0, 0])
        expect(error.result.locales).to eq(%w[en ar])
      end

      expect(portal.reload.articles.pluck(:slug)).to eq(%w[welcome])
    end

    it 'leaves the task rerunnable: the completed rows reapply as unchanged and the rest goes on' do
      expect { seed }.to raise_error(described_class::ApplyFailure)
      write('en', 'zebra', { title: 'Zebra', body: 'Last.', position: 30 })

      result = seed

      expect([result.created, result.updated, result.unchanged]).to eq([2, 0, 1])
      expect(portal.reload.articles.pluck(:slug).sort).to eq(%w[welcome welcome-ar zebra])
      expect(portal.articles.find_by(slug: 'zebra').position).to eq(30)
    end
  end

  describe '.changelog' do
    let!(:changelog_portal) do
      create(:portal, name: 'Lynomia Chat Changelog', slug: Documentation::Library::CHANGELOG_SLUG,
                      platform_owned: true, account: nil,
                      config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en' })
    end

    it 'seeds the changelog corpus into the changelog portal' do
      described_class.changelog.perform!

      expect(changelog_portal.reload.articles).to be_present
      expect(portal.reload.articles).to be_empty
    end
  end
end
