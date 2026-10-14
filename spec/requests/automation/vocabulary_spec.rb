require 'rails_helper'

# THE ONE VOCABULARY, served.
#
# Lynomia's own dashboard carries these lists as JavaScript constants maintained beside the server's. Phase 4's
# Store Syria Automation Studio is the second client, and a second hand-maintained copy is a client that offers a
# merchant an attribute the server rejects -- found when the rule or the flow refuses to save. These examples pin
# that the served vocabulary IS the one the server validates against, by comparing it to the same sources the
# validators read rather than to a list written out here.
RSpec.describe 'Automation vocabulary', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/automation_rules/vocabulary" }
  let(:body) { response.parsed_body }
  let(:conditions) { body['conditions'].index_by { |entry| entry['key'] } }

  it 'is for administrators of the account, like every other automation surface' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    get url, headers: create(:user, account: create(:account), role: :administrator).create_new_auth_token, as: :json
    expect(response.status).to be_in([401, 404])
  end

  context 'when an administrator asks' do
    before { get url, headers: admin.create_new_auth_token, as: :json }

    it 'serves the triggers and actions the rule itself will accept, and no others' do
      rule = AutomationRule.new(account: account)

      expect(body['events'].pluck('name')).to eq(rule.event_names)
      expect(body['actions'].pluck('name')).to eq(rule.actions_attributes)
      # The Commerce triggers this fork adds ride along, because the rule's own list carries them.
      expect(body['events'].pluck('name')).to include('commerce_order_paid', 'commerce_cart_abandoned')
    end

    # An action with no described shape is one a client must not offer: a form that happens to
    # post the right-shaped JSON for a file upload or a webhook is how a half-built action ships.
    it 'describes the shape of each action it describes at all, and marks the rest' do
      actions = body['actions'].index_by { |action| action['name'] }

      expect(actions['change_priority']['fields'].sole)
        .to include('key' => 'priority', 'kind' => 'select', 'wrapped' => true,
                    'values' => %w[low medium high urgent nil])
      expect(actions['resolve_conversation']['fields']).to eq([])
      # Described by nothing, so offered by nothing.
      expect(actions.values_at('send_attachment', 'send_email_to_team').map(&:keys))
        .to eq([%w[name commerce_safe], %w[name commerce_safe]])
      expect(actions['send_whatsapp_template']['fields'].pluck('key')).to eq(%w[inbox_id name language params])
    end

    # The rule Custom::AutomationRule already enforces, reported rather than restated: a Commerce
    # trigger refuses a free-form customer message, so offering one is offering an unsavable rule.
    it 'marks the actions a Commerce trigger would refuse' do
      actions = body['actions'].index_by { |action| action['name'] }
      refused = Custom::AutomationRule::CUSTOMER_MESSAGE_ACTIONS

      expect(actions.values.reject { |action| action['commerce_safe'] }.pluck('name')).to match_array(refused)
      expect(actions['send_whatsapp_template']['commerce_safe']).to be(true)
    end

    it 'serves every standard condition key with the operators the validator checks' do
      yaml = YAML.safe_load(Rails.root.join('lib/filters/filter_keys.yml').read)
      expected = yaml.values_at('conversations', 'contacts', 'messages').flat_map(&:keys)

      expect(conditions.keys).to include(*expected)
      expect(conditions['status']).to include('scope' => 'conversation',
                                              'operators' => yaml.dig('conversations', 'status', 'filter_operators'))
    end

    it 'carries enumerated values from the models own enums, and names a picker for the rest' do
      expect(conditions['status']['values']).to eq(Conversation.statuses.keys)
      expect(conditions['priority']['values']).to eq(Conversation.priorities.keys)
      # An id is this account's own record, so the key names the collection a picker reads rather
      # than listing values that are per account and already served elsewhere.
      expect(conditions.values_at('assignee_id', 'team_id', 'labels').pluck('options_from'))
        .to eq(%w[agents teams labels])
      expect(conditions['status']).not_to have_key('options_from')
    end

    it 'reports a Commerce key as present but unavailable rather than hiding it' do
      # A merchant who cannot use Commerce conditions should see why, not wonder where they went.
      expect(conditions['commerce_order_status']).to include('scope' => 'commerce', 'available' => false)
      expect(conditions['commerce_order_status']['values']).to include('delivered', 'refunded')
      expect(conditions['contact_audience']).to include('scope' => 'audience',
                                                        'operators' => %w[equal_to not_equal_to])
    end

    # Spend is per currency and never converted, so its keys depend on what a store has sold in.
    # Described rather than listed: omitting the family silently would tell a client it does not exist.
    it 'describes the one condition family whose key is not fixed' do
      expect(body['condition_patterns'].first).to include('prefix' => 'commerce_spend_', 'suffix' => 'currency',
                                                          'operators' => %w[is_greater_than is_less_than])
    end
  end

  # The cart trigger is the one the Phase 4A review named: Store Syria's abandoned carts are
  # PRE_UAT, so the trigger is a real name that can never fire for them. Order triggers can.
  it 'separates a trigger whose provider cannot produce the event from one that can' do
    account.enable_features!('lynomia_commerce')
    allow(Automation::Extensions).to receive(:enabled?).and_return(true)
    create(:commerce_store, account: account, provider: 'storesyria', status: :active)

    get url, headers: admin.create_new_auth_token, as: :json
    events = body['events'].index_by { |event| event['name'] }

    expect(events['commerce_order_paid']).to include('available' => true)
    expect(events['commerce_cart_abandoned']).to include('available' => false, 'reason' => 'recovery_unavailable')
  end

  it 'reports a Commerce trigger as unavailable while no store is connected' do
    account.enable_features!('lynomia_commerce')
    allow(Automation::Extensions).to receive(:enabled?).and_return(true)

    get url, headers: admin.create_new_auth_token, as: :json

    expect(body['events'].index_by { |event| event['name'] }['commerce_order_paid'])
      .to include('available' => false, 'reason' => 'no_store')
  end

  it 'offers a Commerce key as available once the account is entitled' do
    account.enable_features!('lynomia_commerce')
    allow(Automation::Extensions).to receive(:enabled?).and_return(true)

    get url, headers: admin.create_new_auth_token, as: :json

    expect(conditions['commerce_order_status']['available']).to be(true)
  end

  it "serves the account's own custom attributes, and never another account's" do
    create(:custom_attribute_definition, account: account, attribute_key: 'loyalty_tier',
                                         attribute_model: 'contact_attribute')
    create(:custom_attribute_definition, account: create(:account), attribute_key: 'foreign_key',
                                         attribute_model: 'contact_attribute')

    get url, headers: admin.create_new_auth_token, as: :json

    expect(conditions['loyalty_tier']).to include('custom_attribute' => true, 'scope' => 'contact_attribute')
    expect(conditions).not_to have_key('foreign_key')
  end
end
