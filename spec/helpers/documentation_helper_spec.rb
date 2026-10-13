require 'rails_helper'

# R1.4 (docs/documentation-v2/08-orchestrator-rulings.md) named the JSON-LD case explicitly, and agent 081
# verified by reading that it is already safe. This file is what keeps it that way: `documentation_structured_data`
# is the one place this product writes author-controlled text into a `<script>` block, and the protection is two
# layers -- `to_json` escapes the string, and `json_escape` turns `<`, `>` and `&` into unicode escapes so a
# `</script>` in an article title cannot terminate the block early.
#
# Also the first spec for this helper at all, which §N.8 of the P0 report recorded as a gap: the breadcrumb
# builder had been covered only through a rendered page.
RSpec.describe DocumentationHelper do
  let(:portal) do
    create(:portal, slug: 'docs-helper-portal', platform_owned: true, account_id: nil,
                    custom_domain: 'docs-helper.example.com',
                    config: { 'allowed_locales' => ['en'], 'default_locale' => 'en', 'layout' => 'documentation' })
  end
  let(:category) { create(:category, portal: portal, account_id: nil, slug: 'helper-cat', locale: 'en') }
  let(:author) { create(:user, account: create(:account), role: :administrator) }

  describe '#documentation_structured_data' do
    it 'escapes a closing script tag in an article title so the block cannot be terminated early' do
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published,
                                 title: 'Pricing</script><script>alert(1)</script>')

      rendered = helper.documentation_structured_data(helper.documentation_article_schema(portal, article))
      parsed = Nokogiri::HTML5.fragment(rendered)

      # One script element, and the payload survives as DATA inside it rather than as markup.
      expect(parsed.css('*').map(&:name)).to eq(['script'])
      expect(parsed.at_css('script')['type']).to eq('application/ld+json')
      expect(rendered).not_to include('</script><script>')
      expect(JSON.parse(parsed.at_css('script').text)['headline']).to eq(article.title)
    end

    it 'escapes the same payload reaching the breadcrumb through a category name' do
      category.update!(name: 'Plans</script><script>alert(1)</script>')
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')

      rendered = helper.documentation_structured_data(helper.documentation_breadcrumb_schema(portal, article))

      expect(Nokogiri::HTML5.fragment(rendered).css('*').map(&:name)).to eq(['script'])
      expect(rendered).not_to include('</script><script>')
    end
  end

  describe '#documentation_article_schema' do
    # R1.4's sibling concern, and the reason the byline rule exists: structured data is the most widely
    # redistributed thing this product emits, so it names the ORGANIZATION and never the author.
    it 'names the portal as author and publisher, never the person who wrote it' do
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')

      schema = helper.documentation_article_schema(portal, article)

      expect(schema['author']).to eq({ '@type' => 'Organization', 'name' => portal.display_title('en') })
      expect(schema['publisher']).to eq({ '@type' => 'Organization', 'name' => portal.display_title('en') })
      expect(schema.to_json).not_to include(author.available_name)
    end
  end

  describe '#documentation_breadcrumb_schema' do
    it 'omits the category crumb for a legacy cross-portal row rather than publishing a foreign name' do
      tenant_account = create(:account)
      tenant_portal = create(:portal, account_id: tenant_account.id, slug: 'helper-tenant-portal')
      foreign = create(:category, portal: tenant_portal, account_id: tenant_account.id,
                                  name: 'ForeignCategoryName', slug: 'foreign-cat', locale: 'en')
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')
      article.update_column(:category_id, foreign.id) # rubocop:disable Rails/SkipsModelValidations

      names = helper.documentation_breadcrumb_schema(portal, article.reload)['itemListElement'].pluck('name')

      expect(names).to contain_exactly(portal.display_title('en'), article.title)
      expect(names).not_to include(foreign.name)
    end

    it 'includes the category crumb when the category is the rendering portal\'s own' do
      article = create(:article, portal: portal, category: category, account_id: nil, author_id: author.id,
                                 locale: 'en', status: :published, title: 'A page')

      names = helper.documentation_breadcrumb_schema(portal, article)['itemListElement'].pluck('name')

      expect(names).to eq([portal.display_title('en'), category.name, article.title])
    end
  end
end
