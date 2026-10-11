require 'rails_helper'

# Sections F and G of docs/p-final/clean-room/01-acceptance-test-plan.md: the properties that only hold once
# all five replacement packages are in place, and the tenant-isolation sweep that is run last.
#
# Everything here is deliberately black-box: an HTTP request, a response body, or a row the product itself
# wrote. The per-package suites prove each package; this one proves they did not re-break each other.
RSpec.describe 'Clean-room cross-package behaviour', type: :request do
  # Both accounts get the same shape of data, so a missing account predicate shows up as a doubled number
  # rather than as nothing at all. A sweep that only creates data on one side cannot catch one.
  let(:tenants) { { mine: build_tenant('cross-mine'), theirs: build_tenant('cross-theirs') } }
  let(:mine) { tenants[:mine] }
  let(:theirs) { tenants[:theirs] }

  # An agent holding every capability the product defines. Section F's question is whether any of them opens a
  # surface that is supposed to be administrator-only, so the test subject has to hold all of them at once.
  let(:role_holder) do
    user = create(:user, account: mine[:account], role: :agent)
    role = create(:custom_role, account: mine[:account], name: 'Everything', permissions: CustomRole::PERMISSIONS)
    mine[:account].account_users.find_by(user_id: user.id).update!(custom_role: role)
    user
  end

  def build_tenant(name)
    account = create(:account, name: name)
    account.enable_features!('audit_logs', 'custom_roles', 'whatsapp_campaign')
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        sync_templates: false, validate_provider_config: false)
    admin = create(:user, account: account, role: :administrator)
    contact = create(:contact, account: account, name: "#{name}-contact", phone_number: "+9655#{rand(1_000_000)}")
    campaign = create(:campaign, account: account, inbox: channel.inbox, campaign_type: :one_off,
                                 scheduled_at: 1.hour.ago)

    { account: account, admin: admin, inbox: channel.inbox, contact: contact, campaign: campaign,
      role: create(:custom_role, account: account, name: "#{name}-role", permissions: %w[contact_manage]) }
  end

  def recipient(tenant, **attributes)
    CampaignRecipient.create!(
      account: tenant[:account], campaign: tenant[:campaign], inbox: tenant[:inbox],
      contact: attributes.delete(:contact) || tenant[:contact], **attributes
    )
  end

  def as(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def account_path(tenant, suffix)
    "/api/v1/accounts/#{tenant[:account].id}/#{suffix}"
  end

  describe 'F-1 the five packages do not re-break each other\'s gates' do
    it 'refuses the trail and set management to an agent holding every capability, but serves campaign results' do
      as(role_holder, :get, account_path(mine, 'audit_logs'))
      expect(response).to have_http_status(:unauthorized)

      as(role_holder, :get, account_path(mine, 'custom_roles'))
      expect(response).to have_http_status(:unauthorized)

      as(role_holder, :post, account_path(mine, 'custom_roles'), { name: 'Mine', permissions: %w[contact_manage] })
      expect(response).to have_http_status(:unauthorized)

      # Campaign results follow the campaign's OWN permission rather than the audit permission. Asserted by
      # comparing the two surfaces for the same actor instead of hard-coding a status: CampaignPolicy is
      # administrator-only today, and the property that must hold is that reading a campaign's results is never
      # a wider permission than reading the campaign.
      as(role_holder, :get, account_path(mine, "campaigns/#{mine[:campaign].id}"))
      reading_the_campaign = response.status
      as(role_holder, :get, account_path(mine, "campaigns/#{mine[:campaign].id}/analytics/metrics"))
      expect(response.status).to eq(reading_the_campaign)

      as(mine[:admin], :get, account_path(mine, "campaigns/#{mine[:campaign].id}/analytics/metrics"))
      expect(response).to have_http_status(:success)
    end
  end

  describe 'F-2 campaign activity is auditable without campaign data leaking into the trail' do
    it 'keeps every recipient phone number and sent body out of the trail' do
      recipient(mine, status: :sent, source_id: 'wamid.leak', sent_at: Time.current,
                      message_content: 'SECRET-BODY-TEXT for you')
      # A campaign edit is a product action, so whatever the trail records about it is recorded here too.
      as(mine[:admin], :patch, account_path(mine, "campaigns/#{mine[:campaign].id}"), { title: 'Renamed' })

      as(mine[:admin], :get, account_path(mine, 'audit_logs'))

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('SECRET-BODY-TEXT')
      expect(response.body).not_to include(mine[:contact].phone_number)
    end
  end

  describe 'F-3 existing data keeps working' do
    # Rows written the way a pre-rewrite database holds them: inserted straight through the connection, with no
    # model callback, no validation and none of this release's code anywhere near them. If the rewrite had
    # reinterpreted a column or needed a migration, these would not read back.
    def insert_legacy_recipients
      CampaignRecipient.statuses.each do |name, value|
        ActiveRecord::Base.connection.exec_insert(
          'INSERT INTO campaign_recipients (account_id, campaign_id, contact_id, inbox_id, status, source_id, ' \
          'created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, now(), now())',
          nil,
          [mine[:account].id, mine[:campaign].id, create(:contact, account: mine[:account]).id,
           mine[:inbox].id, value, "legacy-#{name}"]
        )
      end
    end

    def insert_legacy_audit
      ActiveRecord::Base.connection.exec_insert(
        'INSERT INTO audits (auditable_type, auditable_id, associated_type, associated_id, user_id, user_type, ' \
        'username, action, audited_changes, version, created_at) ' \
        'VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, now())',
        nil,
        [['Inbox', mine[:inbox].id, 'Account', mine[:account].id, mine[:admin].id, 'User',
          'Legacy Admin', 'update', { 'name' => %w[Old New] }.to_json, 1]].flatten
      )
    end

    def insert_legacy_attachment
      ActiveRecord::Base.connection.exec_update(
        'UPDATE account_users SET custom_role_id = $1 WHERE account_id = $2 AND user_id = $3',
        nil, [mine[:role].id, mine[:account].id, mine[:admin].id]
      )
    end

    # Written straight through the connection, so no model callback, no validation and none of this release's
    # code is anywhere near them.
    before do
      insert_legacy_recipients
      insert_legacy_audit
      insert_legacy_attachment
    end

    it 'renders a pre-rewrite audit entry' do
      as(mine[:admin], :get, account_path(mine, 'audit_logs'))

      expect(response).to have_http_status(:success)
      entry = response.parsed_body['audit_logs'].find { |row| row['username'] == 'Legacy Admin' }
      expect(entry).to include('auditable_type' => 'Inbox', 'action' => 'update')
      expect(entry['audited_changes']).to eq('name' => %w[Old New])
    end

    it 'lists a pre-rewrite permission set and keeps a pre-rewrite attachment granting what it granted' do
      as(mine[:admin], :get, account_path(mine, 'custom_roles'))

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.pluck('id')).to include(mine[:role].id)

      membership = mine[:account].account_users.find_by(user_id: mine[:admin].id)
      expect(membership.reload.custom_role_id).to eq(mine[:role].id)
      expect(membership.permissions).to contain_exactly('contact_manage', 'custom_role')
    end

    it 'reads a pre-rewrite recipient in every state without reinterpreting it' do
      as(mine[:admin], :get, account_path(mine, "campaigns/#{mine[:campaign].id}/analytics/metrics"))

      expect(response).to have_http_status(:success)
      # One row per state, written as raw integers: the enum still maps every one of them to the same name.
      expect(response.parsed_body['status_counts']).to eq(
        CampaignRecipient.statuses.keys.index_with { 1 }
      )
      expect(response.parsed_body['audience']).to eq(CampaignRecipient.statuses.size)
    end

    it 'signs in a member holding a pre-rewrite attachment' do
      post '/auth/sign_in', params: { email: mine[:admin].email, password: 'Password1!' }, as: :json

      expect(response).to have_http_status(:success)
      membership = response.parsed_body.dig('data', 'accounts').find { |a| a['id'] == mine[:account].id }
      expect(membership['custom_role_id']).to eq(mine[:role].id)
      expect(membership['custom_role']).to include('name' => mine[:role].name)
    end

    it 'needed no migration to get here' do
      expect(ActiveRecord::Migration.check_all_pending!).to be_nil
    end
  end

  describe 'F-4 the two analytics views agree' do
    it 'reports the same figures per campaign and across campaigns' do
      recipient(mine, status: :sent, source_id: 'wamid.f4a', sent_at: 2.hours.ago)
      recipient(mine, contact: create(:contact, account: mine[:account]), status: :delivered,
                      source_id: 'wamid.f4b', sent_at: 2.hours.ago, delivered_at: 1.hour.ago)
      recipient(mine, contact: create(:contact, account: mine[:account]), status: :read,
                      source_id: 'wamid.f4c', sent_at: 2.hours.ago, read_at: 1.hour.ago)
      recipient(mine, contact: create(:contact, account: mine[:account]), status: :failed,
                      failed_at: 1.hour.ago, error_code: '131026')
      recipient(mine, contact: create(:contact, account: mine[:account]), status: :skipped,
                      error_message: Campaigns::RecipientSnapshot::NO_DESTINATION)

      as(mine[:admin], :get, account_path(mine, "campaigns/#{mine[:campaign].id}/analytics/metrics"))
      per_campaign = response.parsed_body

      cross = Analytics::Campaigns::Metrics.new(
        account: mine[:account],
        date_range: Analytics::DateRange.new(account: mine[:account], since: 1.day.ago.to_date.to_s,
                                             until_value: Date.tomorrow.to_s, group_by: 'day'),
        filters: Analytics::FilterSet.new(account: mine[:account], family: :campaigns,
                                          params: { campaign_id: mine[:campaign].id })
      )

      expect(per_campaign.values_at('sent', 'delivered', 'read', 'failed', 'skipped'))
        .to eq([cross.sent, cross.delivered, cross.read, cross.failed, cross.skipped])
      # The read recipient reached the device, so both views have to count it as delivered.
      expect(per_campaign['delivered']).to eq(2)
    end
  end

  describe 'F-5 nothing references an absent dependency' do
    it 'serves every one of the five areas without a missing constant, file or route' do
      recipient(mine, status: :sent, source_id: 'wamid.f5', sent_at: Time.current, message_content: 'hi')
      campaign_id = mine[:campaign].id

      [
        'audit_logs',
        'custom_roles',
        "campaigns/#{campaign_id}/analytics/metrics",
        "campaigns/#{campaign_id}/analytics/contacts",
        'agents'
      ].each do |path|
        as(mine[:admin], :get, account_path(mine, path))

        expect(response).to have_http_status(:success), "#{path} answered #{response.status}: #{response.body[0, 200]}"
      end
    end

    it 'applies a delivery report through the webhook path without raising' do
      row = recipient(mine, status: :sent, source_id: 'wamid.f5-report', sent_at: Time.current)

      Whatsapp::IncomingMessageBaseService.new(
        inbox: mine[:inbox],
        params: { statuses: [{ id: 'wamid.f5-report', status: 'delivered', timestamp: Time.current.to_i.to_s }] }
          .with_indifferent_access
      ).perform

      expect(row.reload).to be_delivered
    end
  end

  describe 'F-6 the permission vocabulary is complete in the interface' do
    # A permission the server accepts but the editor cannot label would be offered to an administrator as a raw
    # identifier, or not offered at all. The client's own list is the one the editor renders, so the two lists
    # have to agree except for the one value the client deliberately retired.
    let(:client_vocabulary) do
      source = File.read(Rails.root.join('app/javascript/dashboard/constants/permissions.js'))
      source[/AVAILABLE_CUSTOM_ROLE_PERMISSIONS\s*=\s*\[(.*?)\]/m, 1].scan(/'([a-z_]+)'/).flatten
    end

    let(:labels) do
      JSON.parse(File.read(Rails.root.join('app/javascript/dashboard/i18n/locale/en/customRole.json')))
          .dig('CUSTOM_ROLE', 'PERMISSIONS')
    end

    it 'offers every permission it accepts, bar the one deliberately retired, each with a label' do
      expect(CustomRole::PERMISSIONS - CustomRole::RETIRED_PERMISSIONS).to match_array(client_vocabulary)
      expect(CustomRole::PERMISSIONS.map(&:upcase)).to all(satisfy { |key| labels.key?(key) })
      expect(labels.values).to all(be_present)
    end
  end

  # docs/p-final/clean-room/04-integration-contract.md §4 and specs/D §3: production rows exist, so these
  # columns, these enum values and these three indexes are a contract rather than a current state. A guard
  # here is cheaper than finding out from a customer's data.
  describe 'the database contract the five packages share' do
    def indexes(table)
      ActiveRecord::Base.connection.indexes(table)
    end

    def columns(table)
      ActiveRecord::Base.connection.columns(table).to_h { |column| [column.name, column.type] }
    end

    it 'keeps the campaign recipient table as specified' do
      expect(columns('campaign_recipients')).to include(
        'account_id' => :integer, 'campaign_id' => :integer, 'contact_id' => :integer, 'inbox_id' => :integer,
        'source_id' => :string, 'status' => :integer, 'error_code' => :string, 'error_title' => :string,
        'error_message' => :text, 'message_content' => :text, 'sent_at' => :datetime,
        'delivered_at' => :datetime, 'read_at' => :datetime, 'failed_at' => :datetime
      )
    end

    it 'keeps the recipient state names on their production numbers' do
      # `metrics.rb` queries `status: :skipped` and `status: :queued` by name, and the integers are in the rows.
      expect(CampaignRecipient.statuses).to eq(
        'queued' => 0, 'sent' => 1, 'delivered' => 2, 'read' => 3, 'failed' => 4, 'skipped' => 5
      )
    end

    it 'keeps the three recipient indexes that carry behaviour' do
      recipient_indexes = indexes('campaign_recipients')

      one_per_contact = recipient_indexes.find { |index| index.columns == %w[campaign_id contact_id] }
      expect(one_per_contact&.unique).to be(true)

      one_per_provider_id = recipient_indexes.find { |index| index.columns == ['source_id'] }
      expect(one_per_provider_id&.unique).to be(true)
      # Partial, so the recipients Meta has not accepted yet do not collide on a null.
      expect(one_per_provider_id&.where).to include('source_id IS NOT NULL')

      expect(recipient_indexes.map(&:columns)).to include(%w[campaign_id status])
    end

    it 'keeps the audit table, its six indexes, and the three location columns unwritten' do
      expect(columns('audits').keys).to include(
        'auditable_id', 'auditable_type', 'associated_id', 'associated_type', 'user_id', 'user_type',
        'username', 'action', 'audited_changes', 'version', 'comment', 'remote_address', 'request_uuid',
        'created_at', 'city', 'country', 'country_code'
      )
      expect(indexes('audits').map(&:columns)).to include(
        %w[associated_type associated_id created_at], %w[associated_type associated_id],
        %w[auditable_type auditable_id version], ['created_at'], ['request_uuid'], %w[user_id user_type]
      )
      # Lynomia resolves no locations. Nothing this release writes may populate them.
      expect(Custom::AuditLog.where.not(city: nil).or(Custom::AuditLog.where.not(country: nil))).to be_empty
    end

    it 'keeps the permission set table and the membership attachment column' do
      expect(columns('custom_roles')).to include('name' => :string, 'description' => :string,
                                                 'account_id' => :integer, 'permissions' => :text)
      expect(ActiveRecord::Base.connection.columns('custom_roles').find { |c| c.name == 'permissions' }.array?)
        .to be(true)
      expect(columns('account_users')).to include('custom_role_id' => :integer)
    end
  end

  describe 'G tenant isolation sweep' do
    # One row per surface of the sweep table, each attempted from account A against account B's data through
    # every parameter the surface accepts.
    before do
      recipient(theirs, status: :sent, source_id: 'wamid.theirs', sent_at: Time.current,
                        message_content: 'THEIR-SECRET-BODY')
      recipient(mine, status: :sent, source_id: 'wamid.mine', sent_at: Time.current)
      AuditTrail::Event.record(action: 'update', auditable: theirs[:inbox], account: theirs[:account],
                               comment: 'their.event', changes: { 'name' => %w[a THEIR-AUDIT-VALUE] })
    end

    it 'G-1 keeps account B\'s audit entries unreachable under every filter, sort and page' do
      [{}, { sort: 'asc' }, { sort: 'desc' }, { page: 1 }, { page: 2 },
       { user_id: theirs[:admin].id }, { type: 'Inbox' }, { types: ['Inbox'] },
       { since: 10.years.ago.to_i, until: 10.years.from_now.to_i }].each do |params|
        as(mine[:admin], :get, account_path(mine, 'audit_logs'), params)

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('THEIR-AUDIT-VALUE'), "leaked under #{params.inspect}"
        expect(response.parsed_body['audit_logs'].pluck('auditable_id')).not_to include(theirs[:inbox].id)
      end
    end

    it 'G-2 keeps account B\'s permission sets unreachable for read, update, delete and attachment' do
      as(mine[:admin], :get, account_path(mine, 'custom_roles'))
      expect(response.parsed_body.pluck('id')).not_to include(theirs[:role].id)

      as(mine[:admin], :get, account_path(mine, "custom_roles/#{theirs[:role].id}"))
      expect(response).to have_http_status(:not_found)

      as(mine[:admin], :patch, account_path(mine, "custom_roles/#{theirs[:role].id}"), { name: 'Taken over' })
      expect(response).to have_http_status(:not_found)

      as(mine[:admin], :delete, account_path(mine, "custom_roles/#{theirs[:role].id}"))
      expect(response).to have_http_status(:not_found)

      expect(theirs[:role].reload.name).to eq('cross-theirs-role')
    end

    it 'G-3 refuses to attach account B\'s set to account A\'s member' do
      membership = mine[:account].account_users.find_by(user_id: mine[:admin].id)

      as(mine[:admin], :patch, account_path(mine, "agents/#{mine[:admin].id}"),
         { custom_role_id: theirs[:role].id })

      expect(response).to have_http_status(:not_found)
      expect(membership.reload.custom_role_id).to be_nil
    end

    it 'G-4 and G-5 answer 404 for account B\'s campaign at both endpoints and return none of its recipients' do
      ['analytics/metrics', 'analytics/contacts'].each do |suffix|
        as(mine[:admin], :get, account_path(mine, "campaigns/#{theirs[:campaign].id}/#{suffix}"))

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include('THEIR-SECRET-BODY')
      end
    end

    it 'G-6 keeps account B out of the account-wide campaign analytics' do
      as(mine[:admin], :get, account_path(mine, 'analytics/campaigns'),
         { since: 1.day.ago.to_date.to_s, until: Date.tomorrow.to_s })

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('THEIR-SECRET-BODY')
      expect(response.body).not_to include(theirs[:contact].phone_number)
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }
      expect(kpis.dig('recipients_targeted', 'value')).to eq(1)
    end

    it 'G-7 will not let a report routed to account A advance account B\'s recipient' do
      theirs_row = CampaignRecipient.find_by(source_id: 'wamid.theirs')
      before_state = theirs_row.attributes.except('updated_at')

      Whatsapp::IncomingMessageBaseService.new(
        inbox: mine[:inbox],
        params: { statuses: [{ id: 'wamid.theirs', status: 'read', timestamp: Time.current.to_i.to_s }] }
          .with_indifferent_access
      ).perform

      expect(theirs_row.reload.attributes.except('updated_at')).to eq(before_state)
    end
  end
end
