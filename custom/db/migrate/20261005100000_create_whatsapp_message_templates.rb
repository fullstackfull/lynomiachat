# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/02-local-record-design.md): the templates an
# account manages, both local drafts Meta has never seen and the mirror of the templates Meta holds. Meta stays
# authoritative for remote status; this table is where a draft lives and where lifecycle timestamps are kept, because
# the channel's message_templates jsonb is replaced wholesale on every sync and cannot hold local state.
# Identity follows Meta's -- (WABA, name, language) -- scoped to the account. The jsonb snapshot is unchanged.
class CreateWhatsappMessageTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_message_templates do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :business_account_id, null: false
      t.string :name, null: false
      t.string :language, null: false
      t.string :category, null: false
      t.string :parameter_format, null: false, default: 'POSITIONAL'
      t.jsonb :components, null: false, default: []
      t.string :meta_template_id
      t.string :meta_status
      t.jsonb :meta_payload, null: false, default: {}
      t.datetime :meta_synced_at
      t.datetime :submitted_at
      t.string :submission_error, limit: 1000
      t.timestamps
    end

    add_identity_indexes
  end

  private

  def add_identity_indexes
    # Meta's identity, scoped to the tenant: one WABA can never overwrite another's same-named template, and a name
    # alone never deduplicates. Language is case-folded only for uniqueness -- the stored value stays as Meta gives it
    # (en_US), because that is what a submit has to send.
    add_index :whatsapp_message_templates,
              'account_id, business_account_id, name, lower(language)',
              unique: true, name: 'index_whatsapp_message_templates_on_identity'

    # Two rows can never mirror one remote template. Partial, so the many drafts with no id do not collide.
    add_index :whatsapp_message_templates, [:account_id, :meta_template_id],
              unique: true, where: 'meta_template_id IS NOT NULL',
              name: 'index_whatsapp_message_templates_on_meta_id'
  end
end
