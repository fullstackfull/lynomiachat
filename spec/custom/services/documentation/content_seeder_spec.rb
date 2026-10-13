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
  # point: a silent skip would ship a corpus with a hole in it.
  it 'refuses a file with no front matter' do
    root.join('en', 'getting-started', 'broken.md').write("Just a body.\n")

    expect { seed }.to raise_error(ArgumentError, /front matter/)
  end

  it 'refuses a file whose front matter has no title' do
    root.join('en', 'getting-started', 'broken.md').write("---\nposition: 20\n---\nBody.\n")

    expect { seed }.to raise_error(KeyError)
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
