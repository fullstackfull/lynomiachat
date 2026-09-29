# frozen_string_literal: true

class CreateBillingSubscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :billing_subscriptions do |t|
      # accounts.id is integer in Chatwoot, so keep the same type
      t.references :account, type: :integer, null: false,
                             index: { unique: true },
                             foreign_key: { on_delete: :cascade }
      t.references :plan, foreign_key: { to_table: :billing_plans }
      # plan that takes effect at the start of the next period (upgrade/downgrade)
      t.references :scheduled_plan, foreign_key: { to_table: :billing_plans }

      t.string   :status, null: false, default: 'inactive' # inactive | trialing | active | past_due | canceled
      t.string   :source, null: false, default: 'stripe'   # stripe | manual (granted by super admin)
      t.integer  :quantity, null: false, default: 1        # used by per_agent plans
      t.datetime :trial_ends_at
      t.datetime :current_period_end
      t.datetime :grace_period_ends_at
      t.boolean  :cancel_at_period_end, null: false, default: false

      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.string :stripe_price_id
      t.string :stripe_schedule_id
      t.timestamps
    end

    add_index :billing_subscriptions, :status
    add_index :billing_subscriptions, :stripe_customer_id
    add_index :billing_subscriptions, :stripe_subscription_id, unique: true
  end
end