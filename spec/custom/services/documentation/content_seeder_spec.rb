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
