# Lets a plan say which channel types it sells (docs/p11/03-plans-entitlements.md).
#
# P10 named this as the one real P11 dependency: "disable a channel for an account" is not a capability this
# product has. Of the twelve channel types only five have an account feature flag at all
# (channel_email, channel_facebook, channel_website, channel_instagram, channel_tiktok), channel_voice is
# Enterprise-licensed and therefore not assignable here, and WhatsApp -- the channel this product is built
# around -- has none. Where a flag does exist it is enforced in the frontend only.
#
# WHY NOT REUSE THE channel_* FEATURE FLAGS
#   Because P11.4 asks for the opposite. A feature flag is availability and rollout; an entitlement is what a
#   subscription bought. Keeping them separate is what lets a capability require BOTH, and it avoids
#   inventing seven new account flags whose absence on every existing account would lock those channels off
#   the moment anything enforced them.
#
# WHY AN EMPTY LIST MEANS "NO OPINION"
#   This is the backward-compatibility rule the phase turns on. A plan that lists no channels denies none, so
#   every existing plan and every existing account behaves exactly as it does today, and a plan only starts
#   gating channels when an operator deliberately fills the list in. There is no backfill, and no account can
#   be locked out by deploying this.
#
# ROLLBACK
#   remove_column. Billing::Entitlements treats a missing or empty list as "allow", which is the same answer.
class AddChannelEntitlementsToBillingPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :billing_plans, :channel_entitlements, :jsonb, default: [], null: false
  end
end
