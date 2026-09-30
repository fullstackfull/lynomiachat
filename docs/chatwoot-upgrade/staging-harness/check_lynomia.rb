# frozen_string_literal: true

# Lynomia customizations regression (billing lock, limits, billing/platform/mobile endpoints).
# Run unchanged on the 4.14 code and on the upgraded code: usage `rails runner check_lynomia.rb <label>`.
require_relative 'lib'

label = ARGV[0] || 'run'
FakeGraph.reset!
run = Time.now.to_i
settings_before = Billing::Settings.all

account = Account.create!(name: "Tenant L #{run}", locale: 'ar')
admin = User.create!(email: "admin_l#{run}@staging.lynomia.local", name: 'Admin L', password: 'Password1!x', confirmed_at: Time.current)
agent = User.create!(email: "agent_l#{run}@staging.lynomia.local", name: 'Agent L', password: 'Password1!x', confirmed_at: Time.current)
AccountUser.create!(account: account, user: admin, role: :administrator)
AccountUser.create!(account: account, user: agent, role: :agent)
base = "/api/v1/accounts/#{account.id}"

H.check('app boots with custom/ overlay (Billing, MobileAuth constants loaded)',
        defined?(Billing::AccessGuard) && defined?(MobileAuth::SignIn) && Api::V1::Accounts::BaseController.include?(Billing::AccessGuard))
H.check('Account extended by Custom::Account', Account.ancestors.map(&:name).include?('Custom::Account'))

status, = H.api(:get, "#{base}/conversations", admin)
H.check('billing not set up: account stays open', status == 200, "http=#{status}")

plan = BillingPlan.create!(name: "Plan #{run}", price_cents: 1000, currency: 'usd', interval: 'month', pricing_type: 'flat',
                           limits: { 'agents' => 2, 'inboxes' => 1 }, features: [])
Billing::Settings.update!(stripe_secret_key: 'sk_test_staging', stripe_webhook_secret: 'whsec_staging')
account.create_billing_subscription!(status: 'inactive')
status, body = H.api(:get, "#{base}/conversations", admin)
H.check('billing enforced + no active subscription: API locked with 402 subscription_required',
        status == 402 && body.is_a?(Hash) && body['error'] == 'subscription_required', "http=#{status}")
status, = H.api(:get, "#{base}/billing", admin)
H.check('billing API stays reachable while locked', status == 200, "http=#{status}")
status, body = H.api(:get, "#{base}/billing/entitlements", agent)
H.check('entitlements report the lock', status == 200 && body['active'] == false, "http=#{status}")

account.billing_subscription.update!(status: 'active', source: 'manual', plan: plan)
status, = H.api(:get, "#{base}/conversations", admin)
H.check('active subscription: account unlocked', status == 200, "http=#{status}")

status, body = H.api(:post, "#{base}/agents", admin, { name: 'Extra', email: "extra#{run}@staging.lynomia.local", role: 'agent' })
H.check('plan agent limit enforced (422 plan_limit_reached)', status == 422 && body['error'] == 'plan_limit_reached', "http=#{status} #{body}")

status, = H.api(:post, "#{base}/inboxes", admin, { name: 'API 1', channel: { type: 'api' } })
H.check('first inbox within plan limit', status == 200, "http=#{status}")
status, body = H.api(:post, "#{base}/inboxes", admin, { name: 'API 2', channel: { type: 'api' } })
H.check('plan inbox limit enforced', status == 422 && body.to_s.include?('Your plan allows up to 1 inboxes'), "http=#{status} #{body.to_s[0, 120]}")

app = PlatformApp.create!(name: "Lynomia admin #{run}")
H.session.get('/platform/api/v1/billing/plans', headers: { 'api_access_token' => app.access_token.token })
H.check('platform billing API works with a Platform App token',
        H.session.response.status == 200 && H.session.response.body.include?("Plan #{run}"), "http=#{H.session.response.status}")
H.session.get('/platform/api/v1/billing/plans', headers: { 'api_access_token' => admin.access_token.token })
H.check('platform billing API rejects a user token', [401, 403].include?(H.session.response.status), "http=#{H.session.response.status}")

H.session.post('/billing/webhooks/stripe', params: '{}', headers: { 'CONTENT_TYPE' => 'application/json', 'Stripe-Signature' => 't=1,v1=bad' })
H.check('Stripe webhook rejects a bad signature (400, not 500)', H.session.response.status == 400, "http=#{H.session.response.status}")

H.session.post('/api/v1/mobile/auth/google', params: {}.to_json, headers: { 'CONTENT_TYPE' => 'application/json' })
H.check('mobile Google sign-in endpoint answers (invalid token -> 401)', H.session.response.status == 401, "http=#{H.session.response.status}")

H.session.get("/mobile/billing/return?checkout=success&account_id=#{account.id}")
H.check('mobile billing return page answers', [200, 302].include?(H.session.response.status), "http=#{H.session.response.status}")

if Rails.public_path.join('vite/.vite/manifest.json').exist? || Rails.public_path.join('vite/manifest.json').exist?
  H.session.get('/app/login')
  H.check('dashboard login page renders Lynomia title', H.session.response.status == 200 && H.session.response.body.include?('<title>Lynomia Chat</title>'),
          "http=#{H.session.response.status}")
else
  puts 'INFO  login page render skipped: no production Vite build in this checkout (checked with screenshots instead)'
end

status, body = H.api(:get, '/api/v1/profile', admin)
H.check('profile API works for a user token', status == 200 && body['email'] == admin.email, "http=#{status}")

InstallationConfig.where(name: %w[BILLING_STRIPE_SECRET_KEY BILLING_STRIPE_WEBHOOK_SECRET]).delete_all if settings_before[:stripe_secret_key].nil?
H.write_results(File.join(__dir__, 'out', "lynomia_#{label}.json"))
