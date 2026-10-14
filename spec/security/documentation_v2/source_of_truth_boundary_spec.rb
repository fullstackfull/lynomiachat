require 'rails_helper'

# WAVE 4, AGENT 6 -- ADVERSARIAL. Everything an operator can POST that the form does not offer, and the two
# ways a seed run can be made to do something the operator did not intend.
#
# Already pinned elsewhere and deliberately not repeated: `meta['doc_key']` surviving a title save and a posted
# article/category `slug` being dropped (spec/controllers/super_admin/documentation_editor_spec.rb).
RSpec.describe 'Documentation source of truth -- adversarial write boundary', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:portal) do
    create(:portal, name: 'Lynomia Chat Documentation', slug: Documentation::Library::DOCS_SLUG,
                    platform_owned: true, account: nil,
                    config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en' })
  end
  let!(:category) { create(:category, portal: portal, account_id: nil, locale: 'en', slug: 'administration', name: 'Administration') }
  let!(:article) do
    create(:article, portal: portal, account_id: nil, category: category, author: super_admin, locale: 'en',
                     slug: 'audit-logs', title: 'Audit logs', content: 'Body', position: 10,
                     content_source_path: 'custom/db/documentation/en/administration/audit-logs.md',
                     seeded_digests: { 'title' => 'real-digest' },
                     meta: { 'doc_key' => 'audit-logs', 'title' => 'SEO title' })
  end

  describe 'a crafted PUT as a signed-in super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    # PROVENANCE IS NOT MASS-ASSIGNABLE. These two columns are the whole merge model: `content_source_path` is
    # the row's claim to a corpus file and `seeded_digests` is what decides which fields the operator owns.
    # Writing either from the form would let an operator freeze a field for ever, or hand their own row the
    # identity of a corpus file.
    it 'cannot write content_source_path or seeded_digests' do
      put "/super_admin/articles/#{article.id}", params: {
        article: { title: 'Edited',
                   content_source_path: 'custom/db/documentation/en/administration/something-else.md',
                   seeded_digests: { 'title' => 'forged', 'description' => 'forged', 'position' => 'forged' } }
      }

      article.reload
      expect(article.title).to eq('Edited')
      expect(article.content_source_path).to eq('custom/db/documentation/en/administration/audit-logs.md')
      expect(article.seeded_digests).to eq('title' => 'real-digest')
    end

    # `meta` IS on the form, so this is the one jsonb column a crafted post can aim at. Two independent guards
    # have to hold: the field permits only its own keys, and `merge_submitted` slices the submission to them.
    it 'cannot add, change or delete an unmanaged meta key' do
      put "/super_admin/articles/#{article.id}", params: {
        article: { meta: { title: 'New SEO', doc_key: 'forged-key', content_source_path: 'forged',
                           seeded_digests: 'forged', anything_else: 'forged' } }
      }

      expect(article.reload.meta).to eq('doc_key' => 'audit-logs', 'title' => 'New SEO')
    end

    # The create path has no stored row, so `stored_meta` is `{}` and the merge has nothing to protect WITH.
    # The field's own slice is therefore the only guard there, and it has to be enough.
    it 'cannot seed a forged doc_key on CREATE either' do
      post '/super_admin/articles', params: {
        article: { portal_id: portal.id, category_id: category.id, title: 'Brand new', content: 'Body',
                   locale: 'en', status: 'draft', position: 20,
                   meta: { title: 'SEO', doc_key: 'audit-logs' } }
      }

      created = Article.find_by(title: 'Brand new')
      expect(created).to be_present
      expect(created.meta).not_to have_key('doc_key')
      expect(created.content_source_path).to be_nil
      expect(created.seeded_digests).to eq({})
    end

    # `views` and `author` are shown but not on the form; `account_id` is the tenancy column and a platform
    # article must never acquire one, because every tenant surface starts from `Current.account.portals`.
    it 'cannot write views, author_id or account_id' do
      victim = create(:user, account: create(:account))

      put "/super_admin/articles/#{article.id}", params: {
        article: { title: 'Edited again', views: 99_999, author_id: victim.id, account_id: victim.account_ids.first }
      }

      article.reload
      expect(article.views).to eq(0)
      expect(article.author_id).to eq(super_admin.id)
      expect(article.account_id).to be_nil
    end

    # Administrate's `scoped_resource` governs FIND, not assignment, so `portal_id` and `category_id` are both
    # mass-assignable from the form. `category_in_same_portal` is what stops the cross-portal row, and it must
    # refuse rather than silently save.
    it 'cannot move a documentation article onto a tenant portal\'s category' do
      tenant_portal = create(:portal, account: create(:account), slug: 'tenant-portal')
      tenant_category = create(:category, portal: tenant_portal, account_id: tenant_portal.account_id, slug: 'tenant-cat')

      put "/super_admin/articles/#{article.id}", params: { article: { category_id: tenant_category.id } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(article.reload.category_id).to eq(category.id)
    end

    # A SECTION's identity is `(slug, locale)` -- `ContentSeeder#upsert_category` is
    # `find_or_initialize_by(slug:, locale:)`. This moved twice. Section I4 removed `slug` from the section form
    # and left `locale`; section J2 removed `locale`; the owner then ruled that `manifest.yml` is the sole author
    # of a section's `name`, `description`, `position` and `icon` too, which leaves nothing editable -- so the
    # whole surface is withheld at the route (`resources :categories, except: [:edit, :update]`).
    #
    # INVERTED TWICE, and both previous expectations are recorded so neither change is silent. It first asserted
    # that a posted `locale` WAS applied (the defect). It then asserted that slug and locale were dropped while
    # `name` saved. Now there is no endpoint at all, which is why one example replaces two: there is no longer a
    # distinction between "which fields does the form drop" and "what does a crafted PUT do".
    it 'has no update endpoint at all, so a crafted PUT changes nothing' do
      put "/super_admin/categories/#{category.id}", params: {
        category: { name: 'Renamed', slug: 'forged', locale: 'ar' }
      }

      expect(response).to have_http_status(:not_found)

      category.reload
      expect(category.slug).to eq('administration')
      expect(category.name).to eq('Administration')
      expect(category.locale).to eq('en')
    end

    # WHY TODAY'S CORPUS WAS NEVER EXPOSED while the hole was open, kept because it names what the only
    # protection used to be: every manifest section ships in both locales, so
    # `validates :locale, uniqueness: { scope: [:slug, :portal_id] }` refused the flip as soon as the sibling
    # existed, and the hole needed a single-locale section to be reachable at all.
    #
    # The model validation is now the third line of defence rather than the first: no route, no permitted
    # param, and only then the validation. Asserted by showing the sibling's presence makes no difference --
    # the request 404s either way, which is what "the earliest shared entry point" buys.
    it 'refuses before the uniqueness validation that used to be the only thing refusing the flip' do
      create(:category, portal: portal, account_id: nil, locale: 'ar', slug: 'administration', name: 'الإدارة')

      put "/super_admin/categories/#{category.id}", params: { category: { name: 'Renamed', locale: 'ar' } }

      expect(response).to have_http_status(:not_found)
      expect(category.reload.locale).to eq('en')
      expect(category.name).to eq('Administration')
    end
  end

  # THE SAME DEFECT I4 CLOSED FOR `slug`, ONE FIELD OVER, on a single-locale section -- now closed, and this
  # block is the end-to-end proof that it is. It previously measured the damage: the operator flipped the
  # locale, the next seed could not find the section it had authored, created a SECOND row at the manifest
  # locale, and left an empty English-named section published at the Arabic section URL that no manifest row
  # authored and no run reported. The single-locale corpus is kept exactly as it was, because that is the only
  # shape in which the hole was ever reachable.
  describe 'a single-locale section an operator tries to re-locale' do
    let(:root) { Pathname.new(Dir.mktmpdir) }

    before do
      portal.update!(config: { 'allowed_locales' => %w[en ar], 'default_locale' => 'en' })
      root.join('manifest.yml').write(<<~YAML)
        sections:
          - slug: administration
            position: 10
            icon: i-lucide-shield
            en:
              name: Administration
              description: Running the workspace.
      YAML
      FileUtils.mkdir_p(root.join('en', 'administration'))
      root.join('en', 'administration', 'audit-logs.md')
          .write("---\ntitle: Audit logs\ndescription: Audit logs description\nposition: 10\n---\n\nBody\n")
      article.destroy!
      Documentation::ContentSeeder.new(portal: portal, root: root).perform!
      sign_in(super_admin, scope: :super_admin)
    end

    after { FileUtils.remove_entry(root) }

    # INVERTED. This example used to begin `expect(section.reload.locale).to eq('ar')` and then assert the two
    # rows, the rebuilt section and the orphan. There is no update endpoint now, so the chain cannot start --
    # and the end-to-end assertion is that it does not. The 404 is asserted rather than assumed, so this stays
    # a test of the route and not merely of the absence of damage.
    it 'cannot re-locale it, so the next seed finds the section it authored and no orphan appears' do
      section = portal.categories.find_by!(slug: 'administration', locale: 'en')
      put "/super_admin/categories/#{section.id}", params: { category: { locale: 'ar' } }

      expect(response).to have_http_status(:not_found)
      expect(section.reload.locale).to eq('en')

      Documentation::ContentSeeder.new(portal: portal, root: root).perform!

      aggregate_failures do
        # ONE row for the section slug, and it is the same row the first seed created -- not a rebuilt one.
        expect(portal.reload.categories.where(slug: 'administration').pluck(:locale)).to eq(%w[en])
        expect(portal.categories.find_by!(slug: 'administration', locale: 'en').id).to eq(section.id)

        # No orphan at the other locale's URL. This is the assertion the fix exists for.
        expect(portal.categories.find_by(slug: 'administration', locale: 'ar')).to be_nil

        # And the article is where it was, on the section that still owns it.
        article_row = portal.articles.find_by!(slug: 'audit-logs')
        expect(article_row.category_id).to eq(section.id)
        expect(article_row.locale).to eq('en')
      end
    end
  end

  # ADOPT_UNTRACKED is the one operator switch that makes the seeder overwrite a row it cannot tell apart from
  # an operator's own writing. It was read as `ENV['ADOPT_UNTRACKED'].present?`, so EVERY non-empty string was
  # ON -- including `0`, `false` and `off`, which is what an operator types to mean the opposite. It is now
  # `ENV['ADOPT_UNTRACKED'] == '1'` (lib/tasks/documentation.rake:47,53), and `1` is the value the task's own
  # instructions already name.
  describe 'the ADOPT_UNTRACKED switch' do
    # INVERTED: this asserted that `0`, `false`, `no`, `off` and `n` were all truthy, which was the defect.
    # It mirrors the task's expression rather than invoking it, as it did before -- the task body is a Rake
    # block, so the predicate has no seam of its own (that is A6-O1's neighbourhood, not this example's).
    it 'is ON for "1" alone, so every value an operator types to mean off is off' do
      enabled = ->(value) { value.to_s == '1' }

      %w[0 false no off n true yes TRUE 2 1.0].each do |value|
        expect(enabled.call(value)).to be(false), "ADOPT_UNTRACKED=#{value} should not enable adoption"
      end

      expect(enabled.call('1')).to be(true)
      expect(enabled.call('')).to be(false)
      expect(enabled.call(nil)).to be(false)
    end

    # The worst thing one accidental run does, measured end to end on a real untracked row: every class-A and
    # class-C field is taken from the corpus.
    #
    # INVERTED: this asserted `adopted.divergences` was EMPTY, which was A6-O1 -- the run printed `1 adopted` and
    # no divergence line, so an operator never learned which fields the corpus took back. Owner ruling 3's "do not
    # silently continue" closed it: there is now an `:adopted` divergence carrying the class-C fields whose stored
    # value was replaced. Class A stays out of it by design -- the corpus owns prose on every run for every row.
    it 'overwrites an untracked row\'s title, description, position and body, and reports every field it took' do
      root = Pathname.new(Dir.mktmpdir)
      begin
        root.join('manifest.yml').write(<<~YAML)
          sections:
            - slug: administration
              position: 10
              icon: i-lucide-shield
              en:
                name: Administration
                description: Running the workspace.
        YAML
        FileUtils.mkdir_p(root.join('en', 'administration'))
        root.join('en', 'administration', 'audit-logs.md')
            .write("---\ntitle: Corpus title\ndescription: Corpus description\nposition: 70\n---\n\nCorpus body\n")

        # An untracked row: it carries no seeder provenance, exactly like a row created before the migration or
        # by hand in Super Admin.
        article.update!(title: 'An edit worth keeping', description: 'Operator description', position: 10,
                        content: 'Operator body', seeded_digests: {})

        refused = Documentation::ContentSeeder.new(portal: portal, root: root).perform!
        expect([refused.untracked, refused.adopted, refused.updated]).to eq([1, 0, 0])
        expect(article.reload.title).to eq('An edit worth keeping')

        adopted = Documentation::ContentSeeder.new(portal: portal, root: root, adopt_untracked: true).perform!

        article.reload
        aggregate_failures do
          expect(adopted.adopted).to eq(1)
          expect(adopted.divergences.sole.kind).to eq(:adopted)
          expect(adopted.divergences.sole.fields)
            .to eq(%w[title description position meta.title meta.description meta.tags])
          expect(article.title).to eq('Corpus title')
          expect(article.description).to eq('Corpus description')
          expect(article.position).to eq(70)
          expect(article.content).to eq('Corpus body')
        end
      ensure
        FileUtils.remove_entry(root)
      end
    end
  end

  # THE UNIQUE INDEX ON articles.content_source_path, which the brief asks about by name: can two corpus files,
  # or a corpus file and an adopted row, collide and abort a seed mid-way, and what state does that leave?
  describe 'the unique index on content_source_path' do
    let(:root) { Pathname.new(Dir.mktmpdir) }

    before do
      root.join('manifest.yml').write(<<~YAML)
        sections:
          - slug: administration
            position: 10
            icon: i-lucide-shield
            en:
              name: Administration
              description: Running the workspace.
          - slug: automation
            position: 20
            icon: i-lucide-workflow
            en:
              name: Automation
              description: Rules and macros.
      YAML
      %w[administration automation].each { |section| FileUtils.mkdir_p(root.join('en', section)) }
      article.destroy!
    end

    after { FileUtils.remove_entry(root) }

    def write(section, key, title, position = 10)
      root.join('en', section,
                "#{key}.md").write("---\ntitle: #{title}\ndescription: #{title} description\nposition: #{position}\n---\n\nBody of #{key}\n")
    end

    def seed(**) = Documentation::ContentSeeder.new(portal: portal, root: root, **).perform!

    it 'is unreachable from two distinct corpus files, because the path IS the file' do
      write('administration', 'audit-logs', 'Audit logs')
      write('automation', 'macros', 'Macros')

      expect { seed }.not_to raise_error
      expect(portal.reload.articles.pluck(:content_source_path).uniq.length).to eq(2)
    end

    # The shape that DOES lose content, and it is not an index violation: two files with the SAME basename in
    # two sections both derive the same `(slug, locale)`, so there is only ever one row for them.
    #
    # INVERTED: this asserted the collapse -- `1 created, 1 updated` for two files, one row, the later section
    # winning and the first file's prose never published, with nothing raised. Owner ruling 3's preflight refuses
    # the pair as a corpus defect before the first write (P2-SOURCE-OF-TRUTH-CONTRACT.md D9 item 6, F8).
    it 'refuses two sections\' same-named files, rather than collapsing them into one row' do
      write('administration', 'overview', 'Administration overview')
      write('automation', 'overview', 'Automation overview')

      expect { seed }.to raise_error(Documentation::ContentSeeder::PreflightError) do |error|
        expect(error.message).to include('en/administration/overview.md', 'en/automation/overview.md')
      end
      expect(portal.reload.articles).to be_empty
    end

    # A moved file keeps its basename, so the row is found and its path is reassigned. No second row, no
    # violation -- which is what makes the index safe for the move this wave actually contains.
    it 'reassigns the path when a file moves between sections' do
      write('administration', 'auto-resolve', 'Auto resolve')
      seed
      FileUtils.rm(root.join('en', 'administration', 'auto-resolve.md'))
      write('automation', 'auto-resolve', 'Auto resolve')

      expect { seed }.not_to raise_error
      expect(portal.reload.articles.count).to eq(1)
      expect(portal.articles.first.content_source_path).to end_with('en/automation/auto-resolve.md')
    end

    # THE ABORT THAT WAS REACHABLE, and it is on `slug` rather than on `content_source_path`: `articles.slug` is
    # GLOBALLY unique while the seeder's lookup is `(slug, locale)`, so a non-default-locale article whose slug
    # collides with another locale's row is not found and would be INSERTED.
    #
    # INVERTED: this asserted `ActiveRecord::RecordNotUnique` mid-run with `audit-logs` and `audit-logs-ar`
    # already committed -- F7, and the measured instance of A6-O3's "every abort mode leaves partial state".
    # Owner ruling 3 answered A6-O3 with a preflight rather than a transaction, so the pair is refused with
    # nothing written (P2-SOURCE-OF-TRUTH-CONTRACT.md D9 item 6).
    it 'refuses a locale suffix that collides with another row\'s slug, with nothing written' do
      root.join('manifest.yml').write(<<~YAML)
        sections:
          - slug: administration
            position: 10
            icon: i-lucide-shield
            en:
              name: Administration
              description: Running the workspace.
            ar:
              name: الإدارة
              description: إدارة مساحة العمل.
      YAML
      FileUtils.mkdir_p(root.join('ar', 'administration'))
      # This manifest claims only `administration`, and the preflight refuses a corpus directory no section
      # claims, so the `automation` directory the outer before block made has to go or it is what gets reported.
      FileUtils.rm_rf(root.join('en', 'automation'))
      write('administration', 'audit-logs', 'Audit logs')
      # `slug_for('audit-logs-ar', 'en')` is `audit-logs-ar`; `slug_for('audit-logs', 'ar')` is the same string.
      write('administration', 'audit-logs-ar', 'A page whose name ends in the locale suffix')
      root.join('ar', 'administration', 'audit-logs.md')
          .write("---\ntitle: سجلات\ndescription: وصف\nposition: 10\n---\n\nمحتوى\n")

      expect { seed }.to raise_error(Documentation::ContentSeeder::PreflightError) do |error|
        expect(error.message).to include('en/administration/audit-logs-ar.md', 'ar/administration/audit-logs.md')
      end

      # The state an operator is left in: the one the run started from. The category is the group's own
      # fixture, not the run's -- `upsert_category` never executed.
      expect(portal.reload.articles).to be_empty
      expect(portal.categories.pluck(:slug)).to eq([category.slug])
    end
  end
end
