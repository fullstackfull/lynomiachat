# A durable receipt for every billing webhook this installation accepts (docs/p11/04-subscriptions-billing.md).
#
# WHY THIS IS NEEDED, and why nothing existing answers it
#   Nothing recorded that a Stripe event had been received. Three consequences, all live:
#     * No idempotency. The controller returns 500 on any processing error so Stripe retries, and the handler
#       then re-runs from the top -- including a second Stripe::Subscription.retrieve and a second FeatureSync.
#       Stripe also documents that it may deliver the same event more than once on its own.
#     * No ordering. Stripe does not guarantee delivery order, and nothing compared one event against the last
#       one applied, so a delayed `past_due` arriving after `active` won on arrival time rather than on truth.
#     * No observability. P11.44 asks for billing failures in the Operations Center; there was nothing to read.
#
# WHAT IT DELIBERATELY DOES NOT STORE
#   Not the payload. A Stripe event body carries customer details and, for some event types, partial payment
#   instrument data, and none of it is needed to answer "did we process evt_...?". What is kept is the provider
#   event id, its type, its provider-side timestamp, which account it resolved to, when it was processed, and a
#   classified failure string -- the operational facts, and nothing a leak would matter for.
#
# UNIQUENESS
#   provider_event_id is unique, and that index IS the idempotency mechanism: a redelivery loses the insert and
#   is acknowledged rather than processed twice. Concurrency-safe without a lock, because the database decides.
#
# QUERY SHAPES
#   1. have we seen this event?            -> (provider, provider_event_id), unique
#   2. an account's recent billing events  -> (account_id, created_at)
#   3. what is failing right now?          -> (status, created_at), partial on the failures
#
# ROLLBACK
#   drop_table. Idempotency and ordering degrade to the previous behaviour; nothing else reads it.
class CreateBillingWebhookEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :billing_webhook_events do |t|
      t.string :provider, null: false, default: 'stripe'
      t.string :provider_event_id, null: false
      t.string :event_type, null: false
      t.datetime :provider_created_at
      t.integer :account_id
      t.integer :status, null: false, default: 0
      t.string :failure_reason
      t.datetime :processed_at
      t.timestamps
    end

    add_index :billing_webhook_events, [:provider, :provider_event_id],
              unique: true, name: 'uniq_billing_webhook_event_per_provider'
    add_index :billing_webhook_events, [:account_id, :created_at], name: 'index_billing_webhook_events_on_account'
    add_index :billing_webhook_events, [:status, :created_at],
              where: 'status = 2', name: 'index_billing_webhook_events_on_failures'
  end
end
