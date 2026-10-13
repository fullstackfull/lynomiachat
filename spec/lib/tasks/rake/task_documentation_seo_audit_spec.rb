require 'rake'
require 'rails_helper'

# The validator the SEO work is gated on (docs/product-refinement/03-documentation-seo.md §5). A template spec
# asserts the page emits a canonical tag; this asserts that THIS installation's CONTENT produces addresses a
# crawler can use. So the examples here are about data, not markup.
#
# EVERY CHECK THE TASK RUNS HAS AN EXAMPLE HERE, which is the point. The previous suite had six examples for
# ten error checks, and one of those examples passed only by stubbing `Article#slug` so the unique index was
# never touched -- so the release gate's own test suite could not detect a regression in the release gate
# (discovery/098-attack-seo-indexability.md R5). The eight checks that could not fail are gone from the task
# (R1), and what remains is covered.
RSpec.describe Rake::Task do
  describe 'lynomia:docs:seo_audit' do
    subject(:task) { described_class['lynomia:docs:seo_audit'] }

    # One language, so the hreflang-coverage warning does not fire in every example. The bilingual cases get
    # their own portal config below.
    let(:config) { { 'allowed_locales' => ['en'], 'default_locale' => 'en', 'layout' => 'documentation' } }
    let!(:portal) do
      create(:portal, name: 'Lynomia Chat Documentation', slug: 'lynomia-docs', custom_domain: 'docs.example.com',
                      page_title: 'Lynomia Chat Documentation', platform_owned: true, account: nil, config: config)
    end
    let(:english) do
      create(:category, portal: portal, locale: 'en', slug: 'commerce', name: 'Commerce',
                        description: 'Connect a store and work its orders from the inbox.')
    end
    let(:good_description) { 'Connect a WooCommerce store to Lynomia Chat with a REST API key, in four short steps.' }

    before { task.reenable }

    # `doc_key` defaults to the slug, which is what the content seeder writes
    # (custom/app/services/documentation/content_seeder.rb) and what makes the resolution check pass.
    def article(slug:, **attributes)
      create(:article, portal: portal, category: english, status: :published, account: nil, slug: slug,
                       title: 'Connect WooCommerce', description: good_description,
                       meta: { 'doc_key' => slug, 'description' => good_description }, **attributes)
    end

    it 'passes a well-formed article' do
      article(slug: 'connect-woocommerce')

      expect { task.invoke }.to output(/0 error\(s\).*INDEXABLE/m).to_stdout
    end

    it 'says so when there is nothing to audit, rather than claiming success' do
      portal.destroy!

      expect { task.invoke }.to output(/no portal to audit/).to_stdout
    end

    # The alternative to a description is the crawler picking a sentence out of the body, which is rarely the
    # sentence you would have chosen.
    it 'fails an article with no description at all' do
      article(slug: 'no-description', description: nil, meta: { 'doc_key' => 'no-description' })

      expect { expect { task.invoke }.to output(/no meta description and no description.*NOT_INDEXABLE/m).to_stdout }
        .to raise_error(SystemExit)
    end

    it 'warns, without failing, about a description too short to render well' do
      article(slug: 'short', description: 'Too short.', meta: { 'doc_key' => 'short', 'description' => 'Too short.' })

      expect { task.invoke }.to output(/WARN.*description is 10 characters.*0 error\(s\).*INDEXABLE/m).to_stdout
    end

    # THE LENGTH A RESULT PAGE TRUNCATES, which is `article.title` plus the portal suffix. 41 characters of
    # title plus ' | Lynomia Chat Documentation' is 70, and measuring the title alone reported nothing.
    it 'warns about the rendered title, and names the suffix the author cannot shorten' do
      article(slug: 'long-title', title: 'WhatsApp refused the message for one person')

      expect { task.invoke }.to output(/WARN.*rendered <title> is 72 characters \(over 60; 29 of them are the portal suffix\)/m).to_stdout
    end

    it 'does not warn about a title that fits once the suffix is counted' do
      article(slug: 'short-title', title: 'Connect WooCommerce')

      expect { task.invoke }.to output(/0 error\(s\), 0 warning\(s\)/m).to_stdout
    end

    # `meta['doc_key']` is what every in-product help link resolves through, and it is the one field the corpus
    # writes that no Super Admin form input carries -- so a save that replaces `meta` wholesale deletes it and
    # nothing visible breaks until a reader clicks Learn more (P2-WORKSTREAM-OWNERSHIP.md §E1). A file-level
    # spec cannot see this, because the file still has the key.
    it 'fails a platform article with no doc_key' do
      article(slug: 'key-was-dropped', meta: { 'description' => good_description })

      expect { expect { task.invoke }.to output(/no doc_key, so every in-product link/m).to_stdout }
        .to raise_error(SystemExit)
    end

    # Renaming a corpus file makes the seeder create a second row and leave the first published with the same
    # `doc_key` forever, so which article a help link opens becomes a question about row order
    # (P2-SOURCE-OF-TRUTH-CONTRACT.md D4).
    it 'fails when two published articles of one locale claim one doc_key' do
      article(slug: 'connect-woocommerce')
      article(slug: 'connect-woocommerce-renamed', meta: { 'doc_key' => 'connect-woocommerce',
                                                           'description' => good_description })

      expect { expect { task.invoke }.to output(/doc_key 'connect-woocommerce' is claimed by/m).to_stdout }
        .to raise_error(SystemExit)
    end

    # THE CROSS-PORTAL CASE, which the per-portal grouping above cannot see. `Documentation::Library.article_for`
    # searches both platform portals (library.rb), so a changelog entry that claims a documentation article's
    # key wins the lookup when it is the older row -- and the help link lands on the changelog.
    it 'fails when a doc_key resolves to an article in the other platform portal' do
      changelog = create(:portal, name: 'Lynomia Chat Changelog', slug: 'lynomia-changelog',
                                  custom_domain: 'changelog.example.com', page_title: 'Changelog',
                                  platform_owned: true, account: nil, config: config)
      changelog_category = create(:category, portal: changelog, locale: 'en', slug: 'releases', name: 'Releases',
                                             description: 'What changed, and when.')
      create(:article, portal: changelog, category: changelog_category, status: :published, account: nil,
                       slug: 'release-2026-10', title: 'October 2026', description: good_description,
                       meta: { 'doc_key' => 'connect-woocommerce', 'description' => good_description })
      article(slug: 'connect-woocommerce')

      expect { expect { task.invoke }.to output(/doc_key 'connect-woocommerce' resolves to "release-2026-10"/m).to_stdout }
        .to raise_error(SystemExit)
    end

    # Alt text is a public SEO field on these pages, not only an accessibility attribute:
    # `render_markdown_to_plain_text` emits an image's alt text and discards its URL, and that is what the
    # public search payload carries (R2-MEDIA-CONTRACT.md §0.3). The seed boundary refuses an empty alt in a
    # corpus file, so this is the only check on an image an operator inserted in Super Admin.
    it 'fails an article whose image has no alt text' do
      article(slug: 'no-alt', content: "Paste the token.\n\n![](media:whatsapp/connect-number/step-2.png)\n")

      expect { expect { task.invoke }.to output(/1 image\(s\) with empty alt text/m).to_stdout }
        .to raise_error(SystemExit)
    end

    it 'accepts an image that has alt text' do
      article(slug: 'with-alt', content: "Paste the token.\n\n![Step 2: the Token field](media:a/b/step-2.png)\n")

      expect { task.invoke }.to output(/0 error\(s\).*INDEXABLE/m).to_stdout
    end

    # A category page carries its own canonical and its own meta description, and nothing checked either.
    it 'warns about a category with no description, whose section page then has no meta description' do
      article(slug: 'connect-woocommerce')
      english.update!(description: nil)

      expect { task.invoke }.to output(%r{WARN.*categories/commerce.*no description}m).to_stdout
    end

    describe 'with two allowed locales' do
      let(:config) { { 'allowed_locales' => %w[en ar], 'default_locale' => 'en', 'layout' => 'documentation' } }
      let(:arabic) do
        create(:category, portal: portal, locale: 'ar', slug: 'commerce', name: 'التجارة',
                          description: 'اربط متجرك وتابع طلباته من صندوق الوارد.')
      end

      # A crawler ignores an alternate that does not point back, so a one-way link is not a partial win -- it
      # is nothing, and it looks like it works. The audit therefore checks the whole family, not one direction.
      it 'accepts a reciprocal translation pair' do
        root = article(slug: 'connect-woocommerce')
        create(:article, portal: portal, category: arabic, slug: 'connect-woocommerce-ar', status: :published,
                         account: nil, title: 'ربط ووكومرس', description: good_description,
                         associated_article_id: root.id,
                         meta: { 'doc_key' => 'connect-woocommerce', 'description' => good_description })

        expect { task.invoke }.to output(/0 error\(s\), 0 warning\(s\).*INDEXABLE/m).to_stdout
      end

      # THE GAP AN AFTER-THE-FACT AUDIT IS ACTUALLY FOR. A corpus that has lost its Arabic siblings produces a
      # valid set of English-only pages, so every reciprocity check passes and the portal silently stops
      # serving half its readers. A warning, not an error: a translation not yet written is a content state.
      it 'warns when the default-locale article has no published sibling in the other locale' do
        article(slug: 'connect-woocommerce')

        expect { task.invoke }.to output(/WARN.*no published ar sibling.*0 error\(s\)/m).to_stdout
      end

      it 'does not warn about the missing sibling of an article that is itself the translation' do
        root = article(slug: 'connect-woocommerce')
        create(:article, portal: portal, category: arabic, slug: 'connect-woocommerce-ar', status: :published,
                         account: nil, title: 'ربط ووكومرس', description: good_description,
                         associated_article_id: root.id,
                         meta: { 'doc_key' => 'connect-woocommerce', 'description' => good_description })

        expect { task.invoke }.to output(/0 warning\(s\)/m).to_stdout
      end
    end

    # The host is a property of the portal, so it is checked once rather than once per page. The previous check
    # was `canonical.start_with?('http')`, which was true for `https://hc/hc/...` -- the string a blank host
    # used to produce -- so it passed on the one misconfiguration it existed to catch (098 R4).
    describe 'with no host configured anywhere' do
      before { portal.update!(custom_domain: nil) }

      it 'fails the portal once, naming what is unset' do
        article(slug: 'connect-woocommerce')

        with_modified_env(HELPCENTER_URL: nil, FRONTEND_URL: nil) do
          expect { expect { task.invoke }.to output(/ERROR.*lynomia-docs.*no host: neither the portal custom_domain/m).to_stdout }
            .to raise_error(SystemExit)
        end
      end
    end

    # A tenant's help center is their content. A short description there is not a finding about Lynomia's
    # documentation -- and it is not even measurable, because a tenant portal defaults to the `classic` layout
    # whose head emits no canonical, no hreflang and no structured data (098 R6).
    describe 'scoping' do
      # A custom domain so the portal-level host check does not fire and bury the finding each example is
      # about. `ChatwootApp.help_center_root` is nil in the test environment, so a portal without one has no
      # resolvable host at all -- which is itself an error now, and was the one the previous version of this
      # example silently tripped over: the task's `exit 1` escaped the output matcher, so the example asserted
      # nothing while still reporting as passing.
      let!(:tenant_portal) do
        create(:portal, name: "A customer's help center", slug: 'customer-help',
                        custom_domain: 'help.customer.example', config: config)
      end
      let!(:tenant_article) do
        create(:article, portal: tenant_portal, account: tenant_portal.account, status: :published,
                         slug: 'tenant-article', title: 'Ours', description: nil, meta: {})
      end

      before { article(slug: 'connect-woocommerce') }

      it 'passes, although the tenant article has neither a description nor a doc_key' do
        expect { task.invoke }.to output(/0 error\(s\).*INDEXABLE/m).to_stdout
      end

      it 'does not name the tenant article at all' do
        expect { task.invoke }.not_to output(/tenant-article/).to_stdout
      end

      it 'audits a tenant portal only when PORTAL_SLUG names it' do
        with_modified_env(PORTAL_SLUG: 'customer-help') do
          expect { expect { task.invoke }.to output(/no meta description and no description/m).to_stdout }
            .to raise_error(SystemExit)
        end
      end

      # The doc_key checks are a documentation contract, not an SEO rule, so they do not fire on a tenant's own
      # content even when PORTAL_SLUG points the task at it.
      it 'does not ask a tenant article for a doc_key' do
        tenant_article.update!(description: good_description, meta: { 'description' => good_description })

        with_modified_env(PORTAL_SLUG: 'customer-help') do
          expect { task.invoke }.to output(/0 error\(s\).*INDEXABLE/m).to_stdout
        end
      end
    end
  end
end
