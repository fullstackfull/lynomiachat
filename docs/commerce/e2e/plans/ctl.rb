# Control runner for the plan store-limit E2E (docs/commerce/35-stores-on-plans.md). Run with `rails runner`.
#
#   setup            a separate account (Lynomia Plans Demo, admin_p@…) on a manual "Commerce Starter" subscription
#                    (1 store) with a "Commerce Growth" plan (3 stores) next to it, the E2E super admin, and test stores
#                    A2/A3 free to connect (only rows of the disposable local test stores are removed)
#   stripe_price <plan> <on|off>   give the plan a Stripe price (listed on the subscription page) or none (granted only)
#   state            the account's stores, its plan and the plan's limits
#   teardown         the account, its user, its stores and both plans removed
require 'json'

def report(result) = puts("SIM #{result.to_json}")

PASSWORD = 'Password1!x'.freeze
TEST_STORES = %w[http://localhost:8082 http://localhost:8083].freeze
PLANS = { 'starter' => ['Commerce Starter', 1], 'growth' => ['Commerce Growth', 3] }.freeze

def account_p = Account.find_by(name: 'Lynomia Plans Demo')

def plan(key) = BillingPlan.find_by!(name: PLANS.fetch(key).first)

def state
  account = account_p
  subscription = account.billing_subscription
  { account_id: account.id, plan: subscription.plan.name, limits: subscription.plan.limits,
    stores: account.commerce_stores.order(:id).map { |store| { name: store.name, provider: store.provider, status: store.status } },
    connected: account.commerce_stores.connected.count,
    plans: PLANS.keys.to_h { |key| [key, plan(key).id] }, subscription_id: subscription.id }
end

case ARGV[0]
when 'setup'
  SuperAdmin.find_or_create_by!(email: 'super@commerce.lynomia.local') do |user|
    user.assign_attributes(name: 'Super Admin', password: PASSWORD, password_confirmation: PASSWORD, confirmed_at: Time.current)
  end
  Commerce::Store.where(base_url: TEST_STORES).find_each(&:destroy!)
  account = account_p || Account.create!(name: 'Lynomia Plans Demo', locale: 'en')
  account.commerce_stores.find_each(&:destroy!)
  account.update!(locale: 'en')
  user = User.find_by(email: 'admin_p@commerce.lynomia.local') ||
         User.create!(email: 'admin_p@commerce.lynomia.local', name: 'Admin P', password: PASSWORD, password_confirmation: PASSWORD,
                      confirmed_at: Time.current)
  AccountUser.find_or_create_by!(account: account, user: user) { |row| row.role = :administrator }
  PLANS.each_with_index do |(key, (name, stores)), index|
    BillingPlan.find_or_initialize_by(name: name).update!(
      description: index.zero? ? 'For one store' : 'For growing brands', price_cents: index.zero? ? 1900 : 4900, currency: 'usd',
      interval: 'month', pricing_type: 'flat', position: 100 + index, features: ['lynomia_commerce'],
      limits: { 'agents' => 5, 'inboxes' => 3, 'stores' => stores }, stripe_price_id: "price_e2e_commerce_#{key}"
    )
  end
  subscription = BillingSubscription.find_or_initialize_by(account: account)
  subscription.update!(plan: plan('starter'), status: 'active', source: 'manual', quantity: 1, current_period_end: nil)
  account.reload.enable_features!('lynomia_commerce')
  report(state)
when 'stripe_price'
  plan(ARGV[1]).update!(stripe_price_id: ARGV[2] == 'on' ? "price_e2e_commerce_#{ARGV[1]}" : nil)
  report(state)
when 'state'
  report(state)
when 'teardown'
  account = account_p
  if account
    BillingSubscription.where(account: account).delete_all
    account.commerce_stores.find_each(&:destroy!)
    account.destroy!
  end
  User.find_by(email: 'admin_p@commerce.lynomia.local')&.destroy!
  BillingPlan.where(name: PLANS.values.map(&:first)).destroy_all
  report({ account: Account.exists?(name: 'Lynomia Plans Demo'), plans: BillingPlan.where(name: PLANS.values.map(&:first)).count })
end
