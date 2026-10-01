# Lynomia Commerce: one row per order action an agent requested, and per recovery message an agent prepared
# (docs/commerce/28-commerce-actions-architecture.md). Ids, codes, amounts and times only: never tokens, addresses,
# customer or order payloads, or payment data.
class CreateCommerceActionRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :commerce_action_runs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :commerce_store, index: false, foreign_key: { on_delete: :nullify }
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :provider, null: false
      t.string :action_type, null: false
      t.string :external_resource_id, null: false
      t.string :idempotency_key, null: false
      t.string :request_digest, null: false
      t.integer :status, null: false, default: 0
      t.string :provider_request_id
      t.datetime :started_at
      t.datetime :completed_at
      t.string :error_code
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :commerce_action_runs, :idempotency_key, unique: true
    add_index :commerce_action_runs, [:commerce_store_id, :external_resource_id, :status], name: 'index_commerce_action_runs_on_store_resource_status'
    add_index :commerce_action_runs, [:status, :updated_at]
  end
end
