require 'rails_helper'

# P8.8: one place that proves every P8 read surface is account-scoped, against a MIRRORED fixture -- two
# accounts given the same shape of data, so a missing account predicate shows up as a doubled number rather
# than as nothing at all. A spec that only creates data in one account cannot catch a missing predicate.
# File-scope locals rather than constants: the example groups below close over them at definition time, and
# nothing is added to Object.
analytics_endpoints = %w[overview whatsapp campaigns automations flows commerce].freeze

# The two tables the discovery flagged as having NO account_id of their own: `audits` scopes through
# associated_type, and `contact_inboxes` has no account column at all (docs/p8/00-discovery.md §7). Any join
# through them would need an explicit account predicate on the other side, which is easy to forget -- so P8
# reads neither, and this list is what the guard below checks.
account_less_tables = %w[audits contact_inboxes].freeze

RSpec.describe 'P8 tenant isolation', type: :request do
  include_context 'with commerce encryption'

  let(:range) { { since: 6.days.ago.to_date.to_s, until: Date.current.to_s } }

  # Two accounts, each with the same shape of activity, so any unscoped query returns twice what it should.
  let!(:mine) { build_tenant('tenant-mine') }
  let!(:theirs) { build_tenant('tenant-theirs') }

  def p8_source_globs
    ['custom/app/services/analytics/**/*.rb',
     'custom/app/services/contacts/**/*.rb',
     'custom/app/controllers/api/v1/accounts/analytics_controller.rb',
     'custom/app/controllers/api/v1/accounts/contacts/activity_controller.rb']
  end

  def build_tenant(name)
    account = create(:account, name: name, settings: { 'reporting_timezone' => 'Asia/Kuwait' })
    inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                      validate_provider_config: false).inbox
    contact = create(:contact, account: account)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 3.days.ago)

    seed_conversation_activity(account, inbox, conversation)
    seed_campaign_activity(account, inbox, contact, name)
    seed_automation_and_flow_activity(account, conversation, name)
    seed_commerce_activity(account, contact, name)

    { account: account, contact: contact, admin: create(:user, account: account, role: :administrator) }
  end

  def seed_conversation_activity(account, inbox, conversation)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     status: :read, created_at: 2.days.ago)
    ReportingEvent.create!(name: 'conversation_resolved', value: 60, account_id: account.id, inbox_id: inbox.id,
                           conversation_id: conversation.id, event_start_time: 3.days.ago,
                           event_end_time: 2.days.ago, created_at: 2.days.ago)
  end

  def seed_campaign_activity(account, inbox, contact, name)
    campaign = create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: contact,
                              status: :read, source_id: "wamid.#{name}", sent_at: 2.days.ago,
                              delivered_at: 2.days.ago, read_at: 2.days.ago, created_at: 2.days.ago)
  end

  def seed_automation_and_flow_activity(account, conversation, name)
    rule = create(:automation_rule, account: account, event_name: 'conversation_resolved', execution_delay: 30)
    AutomationRulePendingExecution.create!(automation_rule: rule, conversation: conversation,
                                           account_id: account.id, episode_key: "status:#{name}",
                                           due_at: 1.hour.from_now, status: :executed,
                                           created_at: 3.days.ago, updated_at: 2.days.ago)
    bot = create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil)
    version = FlowVersion.create!(account: account, agent_bot: bot, version: 1, status: :published,
                                  graph: { 'nodes' => [], 'edges' => [] })
    FlowSession.create!(account: account, agent_bot: bot, flow_version: version, conversation: conversation,
                        status: :completed, steps_count: 2, finished_at: 2.days.ago, created_at: 3.days.ago)
  end

  def seed_commerce_activity(account, contact, name)
    store = create(:commerce_store, :zid, account: account)
    Commerce::Cart.create!(account: account, commerce_store: store, provider: 'zid',
                           provider_cart_id: "cart-#{name}", contact: contact, state: :abandoned,
                           first_seen_at: 2.days.ago, last_provider_event_at: 2.days.ago,
                           abandoned_at: 2.days.ago, currency: 'SAR', visible_total: 100.0)
  end

  describe 'analytics endpoints' do
    analytics_endpoints.each do |endpoint|
      it "scopes /analytics/#{endpoint} to the caller's account" do
        get "/api/v1/accounts/#{mine[:account].id}/analytics/#{endpoint}",
            params: range, headers: mine[:admin].create_new_auth_token

        expect(response).to have_http_status(:success)
        # Counts only: a rate, a duration and an average are not "how many rows were seen", so doubling would
        # not show up in them and asserting on them would only produce noise.
        counts = response.parsed_body['kpis']
                         .select { |kpi| kpi['unit'] == 'count' && !kpi['key'].start_with?('avg_', 'average_') }
                         .pluck('value').compact

        # Each tenant has exactly one of everything, so any count above one means the other tenant leaked in.
        expect(counts).to all(be <= 1), "#{endpoint} returned #{counts.inspect}"
        expect(counts).to include(1), "#{endpoint} returned nothing, so the assertion above proves nothing"
      end

      it "refuses /analytics/#{endpoint} to an administrator of the other account" do
        get "/api/v1/accounts/#{mine[:account].id}/analytics/#{endpoint}",
            params: range, headers: theirs[:admin].create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'contact activity timeline' do
    it "returns only the caller's contact's activity" do
      get "/api/v1/accounts/#{mine[:account].id}/contacts/#{mine[:contact].id}/activity",
          params: { limit: 100 }, headers: mine[:admin].create_new_auth_token

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']

      expect(payload).not_to be_empty
      expect(payload.pluck('conversation_id').compact.uniq.length).to be <= 1
    end

    it "refuses the other account's administrator" do
      get "/api/v1/accounts/#{mine[:account].id}/contacts/#{mine[:contact].id}/activity",
          headers: theirs[:admin].create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'answers 404 for a contact id from the other account' do
      get "/api/v1/accounts/#{mine[:account].id}/contacts/#{theirs[:contact].id}/activity",
          headers: mine[:admin].create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the tables with no account column of their own' do
    account_less_tables.each do |table|
      it "is never read by P8 code, so #{table} cannot leak across tenants" do
        # Comment lines are stripped first: these documents explain WHY the two tables are avoided, and naming
        # them in that explanation must not read as using them.
        offenders = p8_source_globs.flat_map { |glob| Dir[Rails.root.join(glob)] }.select do |path|
          code = File.readlines(path).grep_v(/^\s*#/).join
          code.match?(/\b#{table}\b|\b#{table.classify}\b/)
        end

        expect(offenders).to be_empty,
                             "#{table} is referenced by #{offenders.map { |p| p.sub(Rails.root.to_s, '') }.inspect}; " \
                             'it has no account_id, so any read of it needs an explicit account predicate on the other side'
      end
    end
  end
end
