require 'rails_helper'

# The corpus this seeder reads is source: Markdown with YAML front matter, one file per article per locale. These
# are the invariants the seeder cannot check for itself, because it reads one file at a time and never follows a
# link -- and both have been broken in practice. Removing the tenant Help Center left three articles pointing at a
# page that no longer described the product, and the Arabic corpus has drifted from the English one in places
# nothing would otherwise catch.
RSpec.describe Documentation::ContentSeeder do
  root = described_class::DOCS_ROOT
  locales = Documentation::Library::LOCALES

  # Lambdas rather than methods: these are used both while the group is being built and inside the examples, and
  # only the closure is visible in both.
  front_matter = lambda do |path|
    YAML.safe_load(File.read(path)[/\A---\s*\n(.*?)\n---\s*\n/m, 1], permitted_classes: [Date])
  end

  # A file name is the article's stable key: it is what a cross-reference points at, and what the seeder turns into
  # the public slug.
  keys_by_locale = locales.index_with do |locale|
    Dir.glob(root.join(locale, '*', '*.md')).map { |path| File.basename(path, '.md') }.sort
  end
  articles = locales.flat_map { |locale| Dir.glob(root.join(locale, '*', '*.md')).map { |path| [locale, path] } }

  it 'translates every article into every locale' do
    locales.each { |locale| expect(keys_by_locale[locale]).to eq(keys_by_locale[Documentation::Library::DEFAULT_LOCALE]) }
  end

  describe 'cross-references' do
    articles.each do |locale, path|
      it "#{locale}/#{File.basename(path, '.md')} links only to articles that exist" do
        # `[label](target)`, keeping only the bare-key links the corpus uses for its own articles. A URL, an anchor
        # or a path is somebody else's to validate.
        targets = File.read(path).scan(%r{\]\((?!https?:|#|/)([^)\s]+)\)}).flatten.uniq

        expect(targets - keys_by_locale[locale]).to be_empty
      end
    end
  end

  describe 'front matter' do
    articles.each do |locale, path|
      it "#{locale}/#{File.basename(path, '.md')} carries what the seeder reads" do
        expect(front_matter.call(path)['title']).to be_present
        expect(front_matter.call(path)['position']).to be_a(Integer)
      end
    end
  end

  # An article and its translation are one page to a reader switching languages, so they belong in the same
  # category and at the same place in it.
  describe 'placement' do
    keys_by_locale[Documentation::Library::DEFAULT_LOCALE].each do |key|
      it "#{key} sits in the same section and position in every locale" do
        placement = locales.map do |locale|
          path = Dir.glob(root.join(locale, '*', "#{key}.md")).first
          [File.basename(File.dirname(path)), front_matter.call(path)['position']]
        end

        expect(placement.uniq.size).to eq(1)
      end
    end
  end

  # The dashboard's contextual-help registry is the other half of this contract: a key there names a slug here,
  # and a slug that stops existing turns a product link into a 404 that nothing else would catch. The registry is
  # JavaScript, so it is read as text rather than evaluated.
  describe 'the dashboard link registry' do
    registry = Rails.root.join('app/javascript/dashboard/helper/documentationLinks.js').read
    slugs = registry[/DOC_ARTICLES = Object\.freeze\(\{(.*?)\n\}\)/m, 1]
            .to_s.scan(/^\s*\w+:\s*'([a-z0-9-]+)',/).flatten

    it 'is not empty, so a parsing change cannot make this vacuous' do
      expect(slugs.size).to be > 40
    end

    it 'points every key at an article the corpus carries' do
      expect(slugs - keys_by_locale[Documentation::Library::DEFAULT_LOCALE]).to be_empty
    end

    it 'has an article for every WhatsApp error code the server classifies' do
      expect(slugs).to include(*Whatsapp::DeliveryFailure::CODES.keys.map { |code| "whatsapp-error-#{code}" })
    end
  end
end
