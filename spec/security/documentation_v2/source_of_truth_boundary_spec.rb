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
    # `find_or_initialize_by(slug:, locale:)`. Section I4 removed `slug` from the form and LEFT `locale`, which
    # is the other half of the same key. These two examples measure how far that reaches.
    it 'drops a posted slug but accepts a posted locale, which is the other half of the seeder\'s lookup' do
      put "/super_admin/categories/#{category.id}", params: {
        category: { name: 'Renamed', slug: 'forged', locale: 'ar' }
      }

      category.reload
      expect(category.slug).to eq('administration')
      expect(category.name).to eq('Renamed')
      expect(category.locale).to eq('ar')
    end

    # WHY TODAY'S CORPUS IS NOT EXPOSED, measured rather than assumed: every manifest section ships in both
    # locales, and `validates :locale, uniqueness: { scope: [:slug, :portal_id] }` refuses the flip as soon as
    # the sibling exists. So the hole needs a single-locale section to be reachable.
    it 'is refused when the other locale\'s row of the same section already exists' do
      create(:category, portal: portal, account_id: nil, locale: 'ar', slug: 'administration', name: 'الإدارة')

      put "/super_admin/categories/#{category.id}", params: { category: { locale: 'ar' } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(category.reload.locale).to eq('en')
    end
  end

  # THE SAME DEFECT I4 CLOSED FOR `slug`, ONE FIELD OVER, on a single-locale section. Measured end to end: the
  # operator flips the locale, the next seed cannot find the section it authored, creates a SECOND row at the
  # manifest locale, and every article stays on the renamed one -- with its own `locale` rewritten to match by
  # `Article#ensure_locale_in_article` (app/models/article.rb:289-295).
  describe 'a single-locale section whose locale an operator changes' do
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

    it 'makes the next seed create a SECOND section at the manifest locale, leaving an orphan behind' do
      section = portal.categories.find_by!(slug: 'administration', locale: 'en')
      put "/super_admin/categories/#{section.id}", params: { category: { locale: 'ar' } }
      expect(section.reload.locale).to eq('ar')

      Documentation::ContentSeeder.new(portal: portal, root: root).perform!

      aggregate_failures do
        # Two rows now share one section slug, and the manifest authored only one.
        expect(portal.reload.categories.where(slug: 'administration').pluck(:locale).sort).to eq(%w[ar en])
        rebuilt = portal.categories.find_by!(slug: 'administration', locale: 'en')
        expect(rebuilt.id).not_to eq(section.id)

        # THE ARTICLE IS NOT LOST, which is the half I predicted wrong and measured instead: the lookup is
        # `(slug, locale)` on the ARTICLE, the row is still English, so the seeder finds it and reattaches it to
        # the rebuilt section. The residue is the orphan.
        article_row = portal.articles.find_by!(slug: 'audit-logs')
        expect(article_row.category_id).to eq(rebuilt.id)
        expect(article_row.locale).to eq('en')

        # The orphan is what an operator and a reader see: an empty, English-named section published at the
        # ARABIC section URL, which no manifest row authored and no seed run will ever clean up (A5-O2 is the
        # rows direction of the same gap). The seeder reports nothing about it.
        orphan = portal.categories.find_by!(slug: 'administration', locale: 'ar')
        expect(orphan.id).to eq(section.id)
        expect(orphan.name).to eq('Administration')
        expect(orphan.portal_articles).to be_empty
      end
    end
  end

  # ADOPT_UNTRACKED is the one operator switch that makes the seeder overwrite a row it cannot tell apart from
  # an operator's own writing. It is read as `ENV['ADOPT_UNTRACKED'].present?`
  # (lib/tasks/documentation.rake:48,54), so every string is ON -- including the ones an operator types to mean
  # off.
  describe 'the ADOPT_UNTRACKED switch' do
    it 'is ON for "0", "false", "no" and "off", which is how one is enabled by accident' do
      %w[0 false no off n].each do |value|
        expect(value.present?).to be(true), "ADOPT_UNTRACKED=#{value}"
      end
      expect(''.present?).to be(false)
      expect(nil.present?).to be(false)
    end

    # The worst thing one accidental run does, measured end to end on a real untracked row: every class-A and
    # class-C field is taken from the corpus and NOTHING reports what was overwritten -- `record_untracked` is
    # skipped and `kept` is empty, so the run prints `1 adopted` and no divergence line.
    it 'overwrites an untracked row\'s title, description, position and body with no divergence reported' do
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
          expect(adopted.divergences).to be_empty
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
    # two sections both derive the same `(slug, locale)`, so the second silently updates the row the first
    # created. One row for two files, the later section wins, and the run reports `1 created, 1 updated`.
    it 'silently collapses two sections\' same-named files into one row, rather than aborting' do
      write('administration', 'overview', 'Administration overview')
      write('automation', 'overview', 'Automation overview')

      result = seed

      expect(portal.reload.articles.count).to eq(1)
      expect([result.created, result.updated]).to eq([1, 1])
      row = portal.articles.first
      expect(row.title).to eq('Automation overview')
      expect(row.content_source_path).to eq('custom/db/documentation/en/automation/overview.md'.sub('custom/db/documentation',
                                                                                                    root.relative_path_from(Rails.root).to_s))
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

    # THE ONE REACHABLE ABORT, and it is on `slug` rather than on `content_source_path`: `articles.slug` is
    # GLOBALLY unique while the seeder's lookup is `(slug, locale)`, so a non-default-locale article whose slug
    # collides with another locale's row is not found and is INSERTED. The run raises mid-way and leaves
    # everything already written in place -- there is no transaction around `perform!`.
    it 'aborts mid-run, with the earlier rows committed, when a locale suffix collides with another row\'s slug' do
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
      write('administration', 'audit-logs', 'Audit logs')
      # `slug_for('audit-logs-ar', 'en')` is `audit-logs-ar`; `slug_for('audit-logs', 'ar')` is the same string.
      write('administration', 'audit-logs-ar', 'A page whose name ends in the locale suffix')
      root.join('ar', 'administration', 'audit-logs.md')
          .write("---\ntitle: سجلات\ndescription: وصف\nposition: 10\n---\n\nمحتوى\n")

      expect { seed }.to raise_error(ActiveRecord::RecordNotUnique, /slug/)

      # Everything the run got to before the raise is committed. That is the state an operator is left in.
      expect(portal.reload.articles.pluck(:slug)).to contain_exactly('audit-logs', 'audit-logs-ar')
      expect(portal.articles.find_by(slug: 'audit-logs-ar').locale).to eq('en')
    end
  end
end
