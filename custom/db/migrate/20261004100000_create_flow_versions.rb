# Lynomia Flow Builder (docs/flow-builder/03-data-model-and-versioning.md): the graphs of a flow bot (an AgentBot with
# bot_type flow). At most one draft and one published version per bot; a published version is never changed again, so a
# session running on it keeps the graph it started with. Older published versions are archived (history).
class CreateFlowVersions < ActiveRecord::Migration[7.2]
  def change
    create_table :flow_versions do |t|
      t.references :account, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.references :agent_bot, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.integer :version, null: false
      t.integer :status, null: false, default: 0
      t.jsonb :graph, null: false, default: {}
      t.references :created_by, null: true, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :published_by, null: true, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :published_at
      t.timestamps
    end
    add_index :flow_versions, [:agent_bot_id, :version], unique: true
    add_index :flow_versions, :agent_bot_id, unique: true, where: 'status = 0', name: 'index_flow_versions_one_draft'
    add_index :flow_versions, :agent_bot_id, unique: true, where: 'status = 1', name: 'index_flow_versions_one_published'
  end
end
