# Lynomia Flow Builder (docs/flow-builder/05-runtime-and-session.md): where a conversation is in a published flow
# version. Orchestration state only: the messages stay Chatwoot messages, persistent answers go to custom attributes.
# At most one live (active or waiting) session per conversation.
class CreateFlowSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :flow_sessions do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :agent_bot, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :flow_version, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.integer :status, null: false, default: 0
      t.string :current_node_id
      t.jsonb :context, null: false, default: {}
      t.bigint :last_message_id
      t.datetime :wake_at
      t.string :step_token
      t.integer :steps_count, null: false, default: 0
      t.string :failure_code
      t.datetime :finished_at
      t.timestamps
    end
    add_index :flow_sessions, :conversation_id, unique: true, where: 'status IN (0, 1)', name: 'index_flow_sessions_one_live'
    add_index :flow_sessions, [:conversation_id, :created_at]
    add_index :flow_sessions, [:account_id, :agent_bot_id, :status]
  end
end
