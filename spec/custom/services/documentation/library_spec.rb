require 'rails_helper'

# `Documentation::Library` is the one door onto platform documentation content, and `#article_for` is the
# product-to-corpus contract: every in-product "Learn more" link resolves through it
# (app/javascript/dashboard/helper/documentationLinks.js -> /docs/:article_slug ->
# custom/app/controllers/documentation_controller.rb:22).
RSpec.describe Documentation::Library do
  let(:config) { { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' } }
  let!(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: described_class::DOCS_SLUG,
                    custom_domain: 'docs.example.com', platform_owned: true, account: nil, config: config)
  end
  let(:english) { create(:category, portal: portal, account: nil, slug: 'whatsapp', locale: 'en', name: 'WhatsApp') }
  let(:arabic) { create(:category, portal: portal, account: nil, slug: 'whatsapp', locale: 'ar', name: 'واتساب') }

  def article(slug:, category:, doc_key: nil, **attributes)
    create(:article, portal: portal, account: nil, category: category, status: :published, slug: slug,
                     title: slug, meta: { 'doc_key' => doc_key || slug }, **attributes)
  end

  describe '.article_for' do
    it 'prefers the reader\'s own language' do
      root = article(slug: 'connect-whatsapp', category: english)
      translation = article(slug: 'connect-whatsapp-ar', category: arabic, doc_key: 'connect-whatsapp',
                            associated_article_id: root.id)

      expect(described_class.article_for('connect-whatsapp', locale: 'ar')).to eq(translation)
      expect(described_class.article_for('connect-whatsapp', locale: 'en')).to eq(root)
    end

    # Falling back to the default locale is the designed behaviour: a translation that has not been written yet
    # should still answer the reader's question, in the language that exists.
    it 'falls back to the default locale when that language has no translation' do
      root = article(slug: 'connect-whatsapp', category: english)

      expect(described_class.article_for('connect-whatsapp', locale: 'ar')).to eq(root)
    end

    it 'treats the key as a literal slug when no article claims it' do
      root = article(slug: 'connect-whatsapp', category: english, doc_key: 'something-else')

      expect(described_class.article_for('connect-whatsapp')).to eq(root)
    end

    it 'resolves nothing rather than guessing when neither the key nor the slug exists' do
      expect(described_class.article_for('no-such-key')).to be_nil
    end

    it 'ignores a draft, because a draft is authoring state' do
      article(slug: 'connect-whatsapp', category: english, status: :draft)

      expect(described_class.article_for('connect-whatsapp')).to be_nil
    end

    # TWO PUBLISHED ROWS CAN CLAIM ONE KEY. Renaming a corpus file makes the seeder's
    # `find_or_initialize_by(slug:)` miss the existing row and create a second one, while the first stays
    # published with the same `doc_key` forever (P2-SOURCE-OF-TRUTH-CONTRACT.md D4).
    context 'when two published articles of one locale claim one doc_key' do
      let!(:older) { article(slug: 'connect-whatsapp', category: english) }
      let!(:newer) { article(slug: 'connect-whatsapp-v2', category: english, doc_key: 'connect-whatsapp') }

      # The older row is the one already indexed under its public URL and the one a reader arriving from a
      # search result lands on, so a help link and a search result agree.
      it 'opens the older of the two' do
        expect(newer.id).to be > older.id
        expect(described_class.article_for('connect-whatsapp', locale: 'en')).to eq(older)
      end

      # The value assertion above can pass by accident, because without an ORDER BY the row the planner
      # happens to return first is usually the older one -- and "usually" is the defect: it can change between
      # two requests with no write in between. This asserts the guarantee rather than the symptom.
      it 'asks the database for an explicit order rather than taking whatever comes back first' do
        expect(described_class.articles.where("articles.meta->>'doc_key' = ?", 'connect-whatsapp').order(:id).to_sql)
          .to include('ORDER BY')
        expect(described_class.article_for('connect-whatsapp', locale: 'en')).to eq(older)
        expect(described_class.article_for('connect-whatsapp', locale: 'en')).to eq(older)
      end
    end

    # A platform portal belongs to no account, which is what keeps its content out of every tenant surface --
    # and keeps a tenant's content out of this lookup.
    it 'never resolves a tenant article, whatever key it claims' do
      tenant_account = create(:account)
      tenant_portal = create(:portal, account: tenant_account, slug: 'customer-help', config: config)
      tenant_category = create(:category, portal: tenant_portal, account: tenant_account, slug: 'theirs', locale: 'en')
      create(:article, portal: tenant_portal, account: tenant_account, category: tenant_category, status: :published,
                       slug: 'connect-whatsapp', title: 'Theirs', meta: { 'doc_key' => 'connect-whatsapp' })

      expect(described_class.article_for('connect-whatsapp')).to be_nil
    end
  end
end
