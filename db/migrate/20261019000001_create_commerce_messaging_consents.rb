class CreateCommerceMessagingConsents < ActiveRecord::Migration[7.2]
  def change
    create_table :commerce_messaging_consents do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, null: false
      # Transactional and promotional are separate rows because they are separate decisions.
      # A shopper who refuses marketing has not refused to be told their parcel shipped, and a
      # grant for one is never a grant for the other.
      t.integer :purpose, null: false
      t.integer :state, null: false
      # How it was decided, as a short machine-readable token: the shopper's own keyword, an
      # administrator's record of an at-checkout agreement, or the provider telling us the
      # number cannot receive. Prose belongs in a log, not in a column nobody can query.
      t.string :source, limit: 40, null: false
      t.datetime :decided_at, null: false
      # Provenance, and deliberately not evidence of what was said: a message id and the
      # keyword matched, never the message body. A consent table is the last place a customer's
      # words should be copied to.
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
    end

    # ONE DECISION PER CONTACT PER PURPOSE. The current state is what a send-time gate asks
    # for, and a gate that had to reduce a history to an answer would be a gate with an
    # opinion. The history lives in the audit trail, which already records every change.
    add_index :commerce_messaging_consents, [:contact_id, :purpose], unique: true,
                                                                     name: 'index_commerce_consents_on_contact_and_purpose'
    add_index :commerce_messaging_consents, [:account_id, :state]
  end
end
