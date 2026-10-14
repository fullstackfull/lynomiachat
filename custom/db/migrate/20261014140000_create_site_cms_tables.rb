# The official website's content, under operator control.
#
# FOUR TABLES IN ONE MIGRATION because they are one feature with one rollback story and are useless apart: a
# page with no navigation is unreachable, and navigation with no pages points nowhere.
#
# WHY NOT `articles`. docs/official-website/04-information-architecture.md D10 settles it: the Documentation
# V2 seeding contract makes `Article#content` repository-owned and the seeder wins on every run, an
# operator-authored article with no corpus file is `untracked`, and `documentation:content` exits non-zero on
# it -- so marketing content stored as articles would fail the documentation seed on every deploy.
# `Article#slug` is also not operator-editable by design, and a marketing URL is exactly what an operator
# must be able to choose.
#
# --- site_pages -----------------------------------------------------------------------------------------
#
# One row per URL per locale: 96 rows for the 48 pages the site ships, seeded from the repository by
# `Marketing::ContentSeeder` and owned by the operator thereafter.
#
# `kind` + `key` IS THE IDENTITY, AND IT IS NOT THE URL. `key` is stable (`home`, `unified_inbox`) and `slug`
# is the URL segment, which an operator may change on a detail page. Keeping them apart is what makes three
# things work at once: a slug rename leaves a redirect behind without losing the page, the Arabic and English
# siblings of one page stay paired through `[kind, key]` even when their slugs differ, and the controller
# looks a page up by the identity the route gave it rather than by operator input.
#
# NO `translation_id`. D10 proposed a self-join to the sibling locale, copying what hreflang reads for
# articles. `[kind, key]` already pairs them and cannot drift; a nullable foreign key duplicating that is a
# second source of truth for the same fact, and the one that gets out of step is the one hreflang reads.
#
# --- site_nav_links -------------------------------------------------------------------------------------
#
# Either an internal target (`page_kind` + `page_key`) or an external `href`, never both -- enforced in the
# model. An internal link stored as a target rather than a URL is what makes a slug rename safe: the
# navigation follows the page instead of pointing at where it used to be.
#
# --- site_faq_entries -----------------------------------------------------------------------------------
#
# Structured rows rather than a blob, because the FAQPage JSON-LD in W5 has to be generated from the same
# question and answer the reader sees. A blob would let the two diverge, which is the definition of a
# structured-data violation.
#
# --- site_redirects -------------------------------------------------------------------------------------
#
# `from_path` and `to_path` are both root-relative, validated in the model. An absolute `to_path` would be an
# open redirect, and `config.action_controller.raise_on_open_redirects` is on (config/application.rb:39), so
# one would raise in production rather than redirect -- better to refuse it at the boundary.
class CreateSiteCmsTables < ActiveRecord::Migration[7.0]
  def change
    create_pages
    create_nav_links
    create_faq_entries
    create_redirects
  end

  private

  def create_pages
    create_table :site_pages do |t|
      t.string :locale, null: false
      t.string :kind, null: false
      t.string :key, null: false
      t.string :slug, null: false
      t.integer :status, null: false, default: 0
      t.datetime :published_at
      t.string :title, null: false
      t.text :description
      t.string :heading
      t.text :lede
      t.jsonb :sections, null: false, default: []
      t.jsonb :meta, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # The identity, and the URL, each unique within a locale and kind. Two indexes rather than one because
    # they answer the two different lookups the site performs: a standing page by its key, a detail page by
    # the slug in the request.
    add_index :site_pages, [:locale, :kind, :key], unique: true
    add_index :site_pages, [:locale, :kind, :slug], unique: true
    add_index :site_pages, [:kind, :status]
  end

  def create_nav_links
    create_table :site_nav_links do |t|
      t.string :locale, null: false
      t.string :placement, null: false
      t.string :label, null: false
      t.string :href
      t.string :page_kind
      t.string :page_key
      t.integer :position, null: false, default: 0
      t.boolean :visible, null: false, default: true
      t.timestamps
    end

    # The one query every page makes: the visible links for this locale and placement, in order.
    add_index :site_nav_links, [:locale, :placement, :position]
  end

  def create_faq_entries
    create_table :site_faq_entries do |t|
      t.string :locale, null: false
      t.text :question, null: false
      t.text :answer, null: false
      t.string :link_label
      t.string :link_page_kind
      t.string :link_page_key
      t.integer :position, null: false, default: 0
      t.boolean :visible, null: false, default: true
      t.timestamps
    end

    add_index :site_faq_entries, [:locale, :position]
  end

  def create_redirects
    create_table :site_redirects do |t|
      t.string :from_path, null: false
      t.string :to_path, null: false
      t.boolean :permanent, null: false, default: true
      t.string :reason
      t.timestamps
    end

    # Unique, because two redirects from one path is an ambiguity with no correct answer. The lookup happens
    # on a path that would otherwise 404, so it must be a single indexed hit.
    add_index :site_redirects, :from_path, unique: true
  end
end
