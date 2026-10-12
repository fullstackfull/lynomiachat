require 'rake'
require 'rails_helper'

# The validator the SEO work is gated on (docs/product-refinement/03-documentation-seo.md §5). A template spec
# asserts the page emits a canonical tag; this asserts that THIS installation's CONTENT produces addresses a
# crawler can use. So the examples here are about data, not markup.
RSpec.describe Rake::Task do
  describe 'lynomia:docs:seo_audit' do
    subject(:task) { described_class['lynomia:docs:seo_audit'] }

    let(:config) { { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' } }
    let!(:portal) do
      create(:portal, name: 'Lynomia Chat Documentation', slug: 'lynomia-docs', custom_domain: 'docs.example.com',
                      platform_owned: true, account: nil, config: config)
    end
    let(:english) { create(:category, portal: portal, locale: 'en', slug: 'commerce', name: 'Commerce') }
    let(:arabic) { create(:category, portal: portal, locale: 'ar', slug: 'commerce-ar', name: 'التجارة') }
    let(:good_description) { 'Connect a WooCommerce store to Lynomia Chat with a REST API key, in four short steps.' }

    before { task.reenable }

    def article(**attributes)
      create(:article, portal: portal, category: english, status: :published, account: nil,
                       title: 'Connect WooCommerce', description: good_description,
                       meta: { 'description' => good_description }, **attributes)
    end

    it 'passes a well-formed article' do
      article(slug: 'connect-woocommerce')

      expect { task.invoke }.to output(/0 error\(s\).*INDEXABLE/m).to_stdout
    end

    # The alternative to a description is the crawler picking a sentence out of the body, which is rarely the
    # sentence you would have chosen.
    it 'fails an article with no description at all' do
      article(slug: 'no-description', description: nil, meta: {})

      expect { expect { task.invoke }.to output(/no meta description and no description.*NOT_INDEXABLE/m).to_stdout }
        .to raise_error(SystemExit)
    end

    it 'warns, without failing, about a description too short to render well' do
      article(slug: 'short', description: 'Too short.', meta: { 'description' => 'Too short.' })

      expect { task.invoke }.to output(/WARN.*description is 10 characters.*0 error\(s\).*INDEXABLE/m).to_stdout
    end

    # Two pages claiming one canonical is how they compete with each other and both lose.
    it 'fails when two articles claim the same canonical' do
      first = article(slug: 'duplicate')
      allow_any_instance_of(Article).to receive(:slug).and_return(first.slug) # rubocop:disable RSpec/AnyInstance
      article(slug: 'duplicate-two')

      expect { expect { task.invoke }.to output(/share the canonical/m).to_stdout }.to raise_error(SystemExit)
    end

    # A crawler ignores an alternate that does not point back, so a one-way link looks like it works and is
    # worth nothing. The audit therefore checks the whole family, not one direction.
    it 'accepts a reciprocal translation pair' do
      root = article(slug: 'connect-woocommerce')
      create(:article, portal: portal, category: arabic, slug: 'connect-woocommerce-ar', status: :published,
                       account: nil, title: 'ربط ووكومرس', description: good_description,
                       associated_article_id: root.id, meta: { 'description' => good_description })

      expect { task.invoke }.to output(/0 error\(s\).*INDEXABLE/m).to_stdout
    end

    it 'says so when there is nothing to audit, rather than claiming success' do
      portal.destroy!

      expect { task.invoke }.to output(/no portal to audit/).to_stdout
    end
  end
end
