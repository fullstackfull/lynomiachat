# Lynomia Commerce: the durable lifecycle of one provider cart
# (docs/commerce-production/05-cart-state-design.md).
#
# The read-through viewer (Commerce::AbandonedCart in the Redis cache) answers "what is in this cart now". This table
# answers the question the viewer cannot: "what has happened to this cart", which needs to survive the cache. A
# provider completion event can arrive after the cache horizon, and without a row there would be no previous state to
# transition from, so the completion would be unattributable.
#
# `provider_cart_id` is deliberately NOT named after any Zid field. Which of Zid's `id`, `cart_id` or `session_id` is
# stable across a cart's life is not stated in its documentation and is a real-UAT question; the choice therefore lives
# in Commerce::Providers::Zid::CartEvents and may change there without touching this schema.
#
# No raw payload, no checkout URL, no line items, no address, no secret: see the design's §9.
class CreateCommerceCarts < ActiveRecord::Migration[7.2]
  def change
    create_table :commerce_carts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :commerce_store, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :provider_cart_id, null: false

      # Nullable on purpose: a cart may arrive before its customer can be matched, and must still be recorded.
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.references :commerce_customer_link, index: false, foreign_key: { on_delete: :nullify }
      t.string :external_customer_id

      t.integer :state, null: false, default: 0
      t.string :provider_phase
      t.string :currency
      t.decimal :visible_total, precision: 15, scale: 2
      t.integer :item_count

      t.datetime :first_seen_at, null: false
      t.datetime :last_provider_event_at, null: false
      t.datetime :abandoned_at
      t.datetime :completed_at
      t.datetime :targeted_at
      t.string :provider_order_id

      t.timestamps
    end

    # The cart's identity. A store belongs to exactly one account and one provider, so this is strictly stronger than
    # scoping by account or provider as well: two accounts holding the same provider cart id get two rows.
    add_index :commerce_carts, [:commerce_store_id, :provider_cart_id],
              unique: true, name: 'index_commerce_carts_on_store_and_provider_cart_id'
    # The batch sweep, and the per-contact panel read.
    add_index :commerce_carts, [:account_id, :state, :abandoned_at],
              name: 'index_commerce_carts_on_account_state_and_abandoned_at'
    add_index :commerce_carts, [:commerce_store_id, :state]
  end
end
