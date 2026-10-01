# Lynomia Audience: one searchable summary per customer link, of the orders Lynomia last read for it
# (docs/audience/03-commerce-query-model.md). Counts, a date, paid totals per currency and the statuses seen: never
# orders, items, addresses, payments, shipments or customer details. A link without a row has not been read yet.
class CreateCommerceContactMetrics < ActiveRecord::Migration[7.2]
  def change
    create_table :commerce_contact_metrics do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :commerce_customer_link, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.integer :orders_count, null: false
      t.integer :active_orders_count, null: false
      t.datetime :last_purchase_at
      t.jsonb :spend, null: false, default: {}
      t.string :order_statuses, array: true, null: false, default: []
      t.string :payment_statuses, array: true, null: false, default: []
      t.string :shipment_statuses, array: true, null: false, default: []
      t.datetime :fetched_at, null: false
      t.timestamps
    end
  end
end
