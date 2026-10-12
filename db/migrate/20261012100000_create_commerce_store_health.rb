# One operational snapshot per connected store (docs/product-refinement/09-commerce-operations.md).
#
# WHY A TABLE AND NOT AN EVENT LOG. The operator question is "has this store been talking to its provider, and
# if not, since when and with what error" -- a CURRENT answer, not a history. A row per provider request would
# be an unbounded request log inside the product's own database, and the incident HISTORY already has a home:
# Operations::Signal plus its event timeline. So this is strictly one row per store, overwritten in place.
#
# WHAT MAY NEVER GO IN HERE. No payloads, no customer data, no tokens, no Authorization headers, no webhook
# bodies, no provider response bodies and no raw exception text. `last_error_code` and `last_error_reason` hold
# a Commerce::Error code and its already-classified reason, which is the product's own closed vocabulary
# (Commerce::Error::CODES) -- never a provider's prose. Commerce::StoreHealthRecorder is the only writer and it
# enforces that.
class CreateCommerceStoreHealth < ActiveRecord::Migration[7.1]
  def change
    create_table :commerce_store_health do |t|
      # One-to-one, enforced by the unique index rather than by convention: two rows for one store would make
      # every reading of this table ambiguous. Cascades, because a snapshot of a store that no longer exists is
      # not a fact about anything.
      t.references :commerce_store, null: false, index: { unique: true },
                                    foreign_key: { to_table: :commerce_stores, on_delete: :cascade }

      # The provider API. Success is written on a throttle (a read that succeeds every minute must not write
      # every minute); failure and recovery are written immediately.
      t.datetime :last_api_success_at
      t.datetime :last_api_failure_at
      t.string :last_error_code, limit: 40
      t.string :last_error_reason, limit: 60
      t.datetime :last_error_at
      # Reset to zero by the next success, so "3" means three in a row NOW, not three ever.
      t.integer :consecutive_failures, null: false, default: 0

      # Webhooks, counted ONLY after the provider's signature or credentials were accepted: a rejected
      # unauthenticated delivery says nothing about the store's health and anyone on the internet could send one.
      t.datetime :last_webhook_received_at
      t.datetime :last_webhook_processed_at

      t.timestamps
    end
  end
end
