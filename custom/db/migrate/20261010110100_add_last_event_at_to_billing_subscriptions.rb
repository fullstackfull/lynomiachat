# The provider-side timestamp of the newest billing event applied to this subscription
# (docs/p11/04-subscriptions-billing.md).
#
# Stripe does not guarantee delivery order. Without this there was nothing to compare an arriving event
# against, so a delayed `past_due` landing after an `active` would downgrade an account that had already
# recovered -- the exact case P11.54 asks about. Billing::SubscriptionSync now refuses an event older than the
# one it has already applied.
#
# Nullable on purpose: every existing row has applied events whose timestamps were never recorded, and
# inventing one would either reject the next legitimate event or accept a stale one. A nil means "no ordering
# information yet", which accepts the next event and records its timestamp, so the guard becomes effective from
# the first event after deployment without a backfill.
class AddLastEventAtToBillingSubscriptions < ActiveRecord::Migration[7.1]
  def change
    add_column :billing_subscriptions, :last_event_at, :datetime
  end
end
