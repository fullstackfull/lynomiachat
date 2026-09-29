# frozen_string_literal: true

class CreateBillingPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :billing_plans do |t|
      t.string  :name, null: false
      t.text    :description
      # Amount in the smallest currency unit (e.g. cents) - maps 1:1 to Stripe unit_amount
      t.integer :price_cents, null: false, default: 0
      t.string  :currency, null: false, default: 'usd'
      t.string  :interval, null: false, default: 'month'       # month | year
      t.string  :pricing_type, null: false, default: 'flat'    # flat | per_agent
      # { "agents": 5, "inboxes": 3 } - missing key = unlimited
      t.jsonb   :limits, null: false, default: {}
      # ["campaigns", "reports", ...] - names from config/features.yml
      t.jsonb   :features, null: false, default: []
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.string  :stripe_product_id
      t.string  :stripe_price_id
      t.timestamps
    end

    add_index :billing_plans, :active
    add_index :billing_plans, :stripe_price_id, unique: true
  end
end
