require 'rails_helper'

# P-FINAL.34. The deployment that follows this phase crosses P8, P9, P10 and P11 in one step. The property that
# matters most on the morning after is not that the new features work -- it is that an account which existed
# before the release, and which nobody has configured since, behaves exactly as it did.
#
# "Not configured" here means precisely what production is: no billing subscription row, no Stripe credentials,
# no trial plan, no plan, and neither of the two new feature flags. Every assertion below is about something a
# real account does every day, and each one would have failed if a new gate had been left on by default.
RSpec.describe 'An existing account after the combined release', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }

  # An agent reaches a conversation only through inbox membership, which is Chatwoot's own rule and not
  # something this release changed.
  before { create(:inbox_member, user: agent, inbox: inbox) }

  def as(user, verb, path, params = {})
    public_send(verb, "/api/v1/accounts/#{account.id}/#{path}", params: params, headers: user.create_new_auth_token, as: :json)
  end

  # If any of these is false the premise is wrong and every assertion below is meaningless, so they are asserted
  # rather than assumed.
  it 'starts from the state production is actually in' do
    expect(account.billing_subscription).to be_nil
    expect(Billing::Settings.stripe_configured?).to be(false)
    expect(Billing::Settings.enforced?).to be(false)
    expect(account.feature_enabled?('lynomia_support_tickets')).to be(false)
    expect(account.feature_enabled?('lynomia_unified_identity')).to be(false)
    expect(account).to be_active
  end

  describe 'the working day' do
    it 'serves conversations, contacts and inboxes to an agent with no subscription' do
      create(:conversation, account: account, inbox: inbox, contact: contact)

      %w[conversations contacts inboxes labels agents].each do |path|
        as(agent, :get, path)

        expect(response).to have_http_status(:success), "expected #{path} to be served, got #{response.status}"
      end
    end

    # The billing lock is a 402 with error 'subscription_required'. An unconfigured installation must never
    # produce one: that is the trap docs/p11/06-rollout-compatibility.md names, and this is its regression test.
    it 'never answers 402 anywhere on the account API' do
      %w[conversations contacts inboxes campaigns automation_rules].each do |path|
        as(administrator, :get, path)

        expect(response).not_to have_http_status(:payment_required), "#{path} answered the billing lock"
      end
    end

    it 'still lets an administrator create a contact, an inbox and an agent' do
      as(administrator, :post, 'contacts', { name: 'Walk-in', phone_number: '+96512345678' })
      expect(response).to have_http_status(:success)

      as(administrator, :post, 'inboxes', { name: 'New API inbox', channel: { type: 'api', webhook_url: '' } })
      expect(response).to have_http_status(:success)

      as(administrator, :post, 'agents', { name: 'New agent', email: 'new-agent@example.com', role: 'agent' })
      expect(response).to have_http_status(:success)
    end

    it 'still sends a message' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)

      as(agent, :post, "conversations/#{conversation.display_id}/messages", { content: 'Hello' })

      expect(response).to have_http_status(:success)
      expect(conversation.messages.outgoing.count).to eq(1)
    end
  end

  describe 'the new surfaces, which must be inert rather than broken' do
    it 'answers 404 for support cases, because the account has no support module' do
      as(administrator, :get, 'support/tickets')

      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 for contact identities, for the same reason' do
      as(administrator, :get, "contacts/#{contact.id}/identities")

      expect(response).to have_http_status(:not_found)
    end

    # Analytics is not flag-gated; its gate is ReportPolicy#view?, which is the administrator rule the product
    # already had for reports. So this is unchanged behaviour, asserted because the release added the endpoints.
    # The range is required at the boundary, which is why a bare request is a 422 rather than a default window.
    it 'serves analytics to an administrator and refuses an agent' do
      range = { since: '2026-10-01', until: '2026-10-07' }

      as(administrator, :get, 'analytics/overview', range)
      expect(response).to have_http_status(:success)

      as(agent, :get, 'analytics/overview', range)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'reports no plan, no ceilings and an open account' do
      as(administrator, :get, 'billing/entitlements')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('active' => true, 'status' => 'inactive')
      expect(Billing::Entitlements.limit(account, :agents)).to be_nil
      expect(Billing::Entitlements.limit(account, :inboxes)).to be_nil
      expect(Billing::Entitlements.limit(account, :stores)).to be_nil
    end

    it 'allows every channel type, because no plan has an opinion about channels' do
      Channels::Capability::BY_CHANNEL_TYPE.each_key do |channel_type|
        expect(Billing::Entitlements.channel_allowed?(account, channel_type)).to be(true),
                                                                                 "#{channel_type} was withheld"
      end
    end

    # Deploying the release must not create a subscription row, start a trial, or write anything commercial for
    # an account nobody has configured.
    it 'writes no commercial state of its own' do
      as(administrator, :get, 'conversations')
      as(administrator, :get, 'billing/entitlements')

      expect(account.reload.billing_subscription).to be_nil
      expect(BillingSubscription.count).to eq(0)
      expect(BillingEntitlementOverride.count).to eq(0)
    end
  end
end
