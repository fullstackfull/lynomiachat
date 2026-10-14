require 'rails_helper'

# The page row, and the rules an operator editing one must not be able to break.
describe SitePage do
  describe 'the standing pages' do
    # Declared in the model and defined in the route table, so this proves the two agree in BOTH directions:
    # a route added without a key, or a key added without a route, fails here rather than shipping an editor
    # that offers a page at an address that does not exist.
    it 'names exactly the standing routes the route table defines' do
      helpers = Rails.application.routes.url_helpers

      described_class::STANDING_KEYS.each do |key|
        expect(helpers).to respond_to("marketing_#{key}_path")
      end

      routed = Rails.application.routes.routes.filter_map(&:name)
                    .grep(/\Amarketing_[a-z_]+\z/)
                    .map { |name| name.delete_prefix('marketing_') }
      # Not standing pages: the four detail routes take a slug, the quote request is a POST, and `media` and
      # `sitemap` are machine endpoints outside the locale scope.
      other = %w[feature channel solution integration pricing_request media sitemap]
      expect((routed - other).uniq.sort).to eq(described_class::STANDING_KEYS.sort)
    end

    it 'refuses a standing page at a key the route table has no page for' do
      page = described_class.new(locale: 'en', kind: 'standing', key: 'nope', title: 'X')

      expect(page).not_to be_valid
      expect(page.errors[:key].join).to include('not a standing page')
    end

    it 'pins a standing page slug to its key' do
      page = described_class.new(locale: 'en', kind: 'standing', key: 'features', slug: 'renamed', title: 'X')

      expect(page).not_to be_valid
      expect(page.errors[:slug].join).to include('fixed word in the route table')
    end
  end

  describe '#public_path' do
    it 'is the unprefixed address in Arabic and the /en address in English' do
      ar = described_class.new(locale: 'ar', kind: 'standing', key: 'features', title: 'X')
      en = described_class.new(locale: 'en', kind: 'standing', key: 'features', title: 'X')

      expect(ar.public_path).to eq('/features')
      expect(en.public_path).to eq('/en/features')
    end

    it 'carries the slug on a detail page' do
      page = described_class.new(locale: 'en', kind: 'feature', key: 'unified_inbox', title: 'X')
      page.validate

      expect(page.public_path).to eq('/en/features/unified-inbox')
    end

    # The homepage, whose address is the site root since the cutover -- and the one page an operator cannot
    # check any other way while it is a draft.
    it 'adds the preview parameter when asked' do
      page = described_class.new(locale: 'ar', kind: 'standing', key: 'home', title: 'X')

      expect(page.public_path).to eq('/')
      expect(page.public_path(preview: true)).to eq('/?preview=1')
    end
  end

  # The boundary the whole rebuild rests on: the row owns the words and Marketing::Catalog owns the facts.
  describe 'the Marketing::Catalog boundary' do
    let(:page) do
      described_class.create!(locale: 'en', kind: 'feature', key: 'unified_inbox', title: 'Unified inbox',
                              status: :published)
    end

    it "reads a feature's state from the catalogue and not from the row" do
      entry = page.catalogue_entry

      expect(entry).to be_present
      expect(entry.state).to eq(Marketing::Catalog.feature(:unified_inbox).state)
      expect(described_class.column_names).not_to include('state', 'docs', 'related', 'channels')
    end

    # There is no column to write and no form field to write it with, so an operator cannot turn a
    # conditional capability into an available one. Asserted on the editor's own field list.
    it 'has no editable field an operator could use to claim a different state' do
      editable = SitePageDashboard::FORM_ATTRIBUTES_NEW.map(&:to_s)

      expect(editable).not_to include('state', 'status_label', 'docs', 'prerequisite', 'related')
    end
  end
end
