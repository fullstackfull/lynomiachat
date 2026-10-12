require 'rails_helper'

# The public documentation search had no spec at all, which is how a public endpoint ends up trusted on the
# strength of the code reading correctly (docs/product-refinement/06-public-surface-audit.md §1).
#
# Every example here is a property somebody could break without noticing, because the search still *works*
# after each of these regressions -- it just also returns something it should not. The two that matter most
# are the ones a crafted query parameter reaches: `Public::Api::V1::Portals::SearchController#search_params`
# permits `:status`, and `Article.search` feeds it straight to `search_by_status`.
RSpec.describe 'Public documentation search', type: :request do
  let(:docs_config) do
    { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' }
  end

  # `custom_domain` is what satisfies `ensure_custom_domain_request` for a request spec, whose host is
  # www.example.com -- the same arrangement spec/requests/documentation/seo_spec.rb uses.
  let!(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: 'lynomia-docs', custom_domain: 'www.example.com',
                    platform_owned: true, account: nil, config: docs_config)
  end
  let!(:category) { create(:category, portal: portal, locale: 'en', slug: 'commerce', name: 'Commerce') }

  # An article's locale FOLLOWS its category's (Article#ensure_locale_in_article), so an Arabic article needs
  # an Arabic category -- creating one with locale: 'ar' in an English category silently makes it English.
  let!(:arabic_category) { create(:category, portal: portal, locale: 'ar', slug: 'commerce-ar', name: 'التجارة') }

  let!(:published) do
    create(:article, portal: portal, category: category, slug: 'connect-woocommerce', status: :published,
                     account: nil, title: 'Connect WooCommerce',
                     description: 'Connect a WooCommerce store with a REST API key.')
  end

  def search(query, **params)
    get "/hc/#{portal.slug}/en/search", params: { query: query, **params }
  end

  # The documentation layout's sidebar lists the portal's published articles, so a published title appears on
  # the page whether or not it MATCHED. Zero results is therefore asserted on the empty state the template
  # renders for `@articles.empty?`, which cannot be true at the same time as any result.
  # Escaped, because the string carries apostrophes and the template emits them as `&#39;`.
  def no_results_for(query)
    ERB::Util.html_escape(I18n.t('public_portal.search.no_results', query: query))
  end

  it 'finds a published article' do
    search('WooCommerce')

    expect(response).to have_http_status(:success)
    expect(response.body).to include(I18n.t('public_portal.search.found_results', count: 1))
    expect(response.body).not_to include(no_results_for('WooCommerce'))
  end

  it 'never returns a draft' do
    create(:article, portal: portal, category: category, slug: 'unreleased-woocommerce-feature', status: :draft,
                     account: nil, title: 'Unreleased WooCommerce feature', description: 'Not ready yet.')

    search('WooCommerce')

    expect(response.body).to include(published.title)
    expect(response.body).not_to include('Unreleased WooCommerce feature')
  end

  # The controller scopes to `.published` BEFORE `Article.search` applies `search_by_status`, so the two
  # conditions AND into `status = 1 AND status = 0` and the result is empty rather than the draft. Asserted
  # because the protection is an accident of ordering: moving `.published` after the search would leak.
  it 'refuses a crafted status parameter asking for drafts' do
    create(:article, portal: portal, category: category, slug: 'unreleased-woocommerce-feature', status: :draft,
                     account: nil, title: 'Unreleased WooCommerce feature', description: 'Not ready yet.')

    search('WooCommerce', status: 'draft')

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include('Unreleased WooCommerce feature')
  end

  # An unknown enum value becomes `status IS NULL` on this Rails version rather than raising, so a crafted
  # value is an empty result and not a 500 on a public endpoint.
  it 'answers a status parameter that is not a status at all' do
    search('WooCommerce', status: 'bogus')

    expect(response).to have_http_status(:success)
    expect(response.body).to include(no_results_for('WooCommerce'))
  end

  it 'never returns an archived article' do
    create(:article, portal: portal, category: category, slug: 'withdrawn-woocommerce-guide', status: :archived,
                     account: nil, title: 'Withdrawn WooCommerce guide', description: 'Superseded.')

    search('WooCommerce')

    expect(response.body).not_to include('Withdrawn WooCommerce guide')
  end

  # Without this, an empty search box would dump the entire corpus -- including, for a paginated page of ten,
  # whatever happens to sort first.
  it 'returns nothing for a blank query rather than everything' do
    search('')

    expect(response).to have_http_status(:success)
    expect(response.body).to include(no_results_for(''))
  end

  it 'does not return another locale’s article' do
    create(:article, portal: portal, category: arabic_category, slug: 'connect-woocommerce-ar', status: :published,
                     account: nil, title: 'ربط ووكومرس WooCommerce', description: 'اربط متجر ووكومرس.')

    search('WooCommerce')

    expect(response.body).to include(published.title)
    expect(response.body).not_to include('ربط ووكومرس')
  end

  it 'does not return another portal’s article' do
    other = create(:portal, name: 'Other', slug: 'other-docs', custom_domain: 'other.example.com',
                            platform_owned: true, account: nil, config: docs_config)
    other_category = create(:category, portal: other, locale: 'en', slug: 'other-commerce', name: 'Commerce')
    create(:article, portal: other, category: other_category, slug: 'other-woocommerce', status: :published,
                     account: nil, title: 'Other portal WooCommerce guide', description: 'Different site.')

    search('WooCommerce')

    expect(response.body).to include(published.title)
    expect(response.body).not_to include('Other portal WooCommerce guide')
  end

  # The content column is weighted into the search vector, so a term only in the body is findable -- and the
  # rendered result must not be the raw body with it.
  it 'matches on the body and renders no raw markup from it' do
    create(:article, portal: portal, category: category, slug: 'salla-reconnect', status: :published, account: nil,
                     title: 'Reconnect Salla', description: 'Reconnect a Salla store.',
                     content: "A merchant reaches this when the token lapsed.\n\n<script>alert(1)</script>")

    search('lapsed')

    expect(response.body).to include('Reconnect Salla')
    expect(response.body).not_to include('<script>alert(1)</script>')
  end
end
