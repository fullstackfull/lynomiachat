# Lynomia Commerce: one row per connected store (docs/commerce/01-unified-architecture.md §5).
class CreateCommerceStores < ActiveRecord::Migration[7.2]
  def change
    create_table :commerce_stores do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :external_store_id, null: false
      t.string :name, null: false
      t.string :base_url, null: false
      t.integer :status, null: false, default: 0
      t.text :credentials
      t.jsonb :settings, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    add_index :commerce_stores, [:provider, :external_store_id], unique: true
    add_index :commerce_stores, [:account_id, :provider]
  end
end
