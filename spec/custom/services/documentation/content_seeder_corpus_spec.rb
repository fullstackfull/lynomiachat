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
end
