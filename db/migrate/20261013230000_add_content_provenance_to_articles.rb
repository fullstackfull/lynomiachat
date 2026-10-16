# Lynomia global documentation: the two columns that let a deploy know which article rows a corpus file owns and
# what the seeder last wrote into each of their mergeable fields, so a re-seed can leave an operator's edit alone
# instead of silently reverting it (docs/documentation-v2/P2-SOURCE-OF-TRUTH-CONTRACT.md D1, D2).
#
# Additive and `change`-based, so it inverts mechanically and older code simply ignores two more nullable columns.
class AddContentProvenanceToArticles < ActiveRecord::Migration[7.2]
  def change
    # The corpus file that owns this row, relative to Rails.root. NULL means no file owns it: every tenant article,
    # and every row an operator authored by hand. ONE VOCABULARY with the attachment provenance Agent 1 stores in
    # blob metadata under the same name (Documentation::MediaResolver::SOURCE_PATH_METADATA).
    add_column :articles, :content_source_path, :string

    # Per field, the SHA-256 of what the seeder last wrote there -- a digest, never the value, so this is not a
    # second copy of the content. An empty hash on a persisted row means the seeder has never tracked it.
    add_column :articles, :seeded_digests, :jsonb, default: {}, null: false

    # A guarantee rather than an optimisation: one file owns at most one row. PostgreSQL permits unlimited NULLs in
    # a unique index, so every untracked row -- which is every tenant article -- is unaffected.
    add_index :articles, :content_source_path, unique: true
  end
end
