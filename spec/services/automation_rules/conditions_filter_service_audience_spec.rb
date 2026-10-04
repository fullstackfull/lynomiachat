require 'rails_helper'

# The "Contact audience is in / is not in" condition in Chatwoot automation rules
# (docs/automation/03-audience-and-commerce-conditions.md).
RSpec.describe AutomationRules::ConditionsFilterService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:vip) { create(:contact, account: account, email: 'layla@vip.example') }
  let(:regular) { create(:contact, account: account, email: 'omar@mail.example') }
  let(:vip_conversation) { create(:conversation, account: account, inbox: inbox, contact: vip) }
  let(:regular_conversation) { create(:conversation, account: account, inbox: inbox, contact: regular) }
  let(:vip_query) { { 'payload' => [{ 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['vip.example'] }] } }
  let(:shared) { create(:custom_filter, account: account, user: admin, filter_type: :contact, shared: true, name: 'VIP', query: vip_query) }
  let(:personal) { create(:custom_filter, account: account, user: admin, filter_type: :contact, name: 'Mine', query: vip_query) }

  def condition(operator, ids)
    { 'attribute_key' => 'contact_audience', 'filter_operator' => operator, 'values' => ids, 'query_operator' => nil }
  end

  def rule_with(*conditions)
    account.automation_rules.create!(name: 'VIP', event_name: 'conversation_created', conditions: conditions,
                                     actions: [{ 'action_name' => 'add_label', 'action_params' => ['vip'] }])
  end

  def matches?(rule, conversation) = described_class.new(rule, conversation).perform

  it 'matches the contacts of a shared audience, and "is not in" the others' do
    is_in = rule_with(condition('equal_to', [shared.id]))
    is_not_in = rule_with(condition('not_equal_to', [shared.id]))

    expect([matches?(is_in, vip_conversation), matches?(is_in, regular_conversation)]).to eq([true, false])
    expect([matches?(is_not_in, vip_conversation), matches?(is_not_in, regular_conversation)]).to eq([false, true])
  end

  it 'joins the existing condition chain with AND / OR' do
    rule = rule_with(condition('equal_to', [shared.id]).merge('query_operator' => 'AND'),
                     { 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['resolved'], 'query_operator' => nil })

    expect(matches?(rule, vip_conversation)).to be(false)
    vip_conversation.update!(status: :resolved)
    expect(matches?(rule, vip_conversation)).to be(true)
  end

  it 'uses the audience as it is now: an edit changes the next evaluation, nothing is copied into the rule' do
    rule = rule_with(condition('equal_to', [shared.id]))
    expect(matches?(rule, regular_conversation)).to be(false)

    shared.update!(query: { 'payload' => [{ 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['mail.example'] }] })

    expect(matches?(rule, regular_conversation)).to be(true)
    expect(rule.reload.conditions.first['values']).to eq([shared.id])
  end

  it 'evaluates shared audiences with conversation conditions over the account, as no member' do
    open_audience = create(:custom_filter, account: account, user: admin, filter_type: :contact, shared: true, name: 'Open',
                                           query: { 'payload' => [{ 'attribute_key' => 'conversation_status', 'filter_operator' => 'equal_to',
                                                                    'values' => ['open'] }] })
    rule = rule_with(condition('equal_to', [open_audience.id]))

    expect(matches?(rule, vip_conversation)).to be(true)
  end

  it 'asks about the event\'s contact only, never the whole audience, and calls nothing outside' do
    3.times { |index| create(:contact, account: account, email: "other#{index}@vip.example") }
    rule = rule_with(condition('equal_to', [shared.id]))
    queries = []
    callback = lambda do |*, payload|
      binds = payload[:type_casted_binds].respond_to?(:call) ? payload[:type_casted_binds].call : payload[:type_casted_binds]
      queries << [payload[:sql], Array(binds)] if payload[:sql].include?('FROM "contacts"')
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { matches?(rule, vip_conversation) }

    # The audience's own query (its email condition), restricted to this contact's id and to one row.
    membership = queries.select { |sql, _| sql.include?('ILIKE') }
    expect(membership.size).to eq(1)
    sql, binds = membership.first
    expect(sql).to include('"contacts"."id" = $').and(include('LIMIT'))
    expect(binds).to include(vip.id)
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it 'rejects personal audiences, another account\'s audiences and unknown ids when the rule is saved' do
    other_account = create(:account)
    foreign = create(:custom_filter, account: other_account, user: create(:user, account: other_account), filter_type: :contact,
                                     shared: true, query: vip_query)

    [personal.id, foreign.id, 0].each do |id|
      rule = account.automation_rules.new(name: 'x', event_name: 'conversation_created', conditions: [condition('equal_to', [id])],
                                          actions: [{ 'action_name' => 'add_label', 'action_params' => ['vip'] }])
      expect(rule).not_to be_valid
      expect(rule.errors[:conditions].join).to include('shared audiences of this account')
    end

    bad_operator = account.automation_rules.new(name: 'x', event_name: 'conversation_created',
                                                conditions: [condition('contains', [shared.id])], actions: [])
    expect(bad_operator).not_to be_valid
  end

  it 'never matches through an audience that is no longer shared' do
    rule = rule_with(condition('equal_to', [shared.id]))
    shared.update!(shared: false)

    expect(matches?(rule, vip_conversation)).to be(false)
  end

  it 'adds the label through the existing listener and actions for members only' do
    rule_with(condition('equal_to', [shared.id]))
    [vip_conversation, regular_conversation].each do |conversation|
      AutomationRuleListener.instance.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: conversation))
    end

    expect(vip_conversation.reload.label_list).to eq(['vip'])
    expect(regular_conversation.reload.label_list).to be_empty
  end

  it 'stops only the Lynomia conditions when the extensions are switched off' do
    rule = rule_with(condition('equal_to', [shared.id]))
    status_rule = account.automation_rules.create!(name: 'Open', event_name: 'conversation_created', actions: [],
                                                   conditions: [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to',
                                                                  'values' => ['open'], 'query_operator' => nil }])

    with_modified_env LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED: 'false' do
      expect(matches?(rule, vip_conversation)).to be(false)
      expect(matches?(status_rule, vip_conversation)).to be(true)
      expect(account.automation_rules.new(name: 'x', event_name: 'conversation_created', conditions: [condition('equal_to', [shared.id])],
                                          actions: [])).not_to be_valid
    end
  end

  it 'names the installation, not a hard-coded product, when it refuses a rule because the extensions are off' do
    InstallationConfig.where(name: 'INSTALLATION_NAME').first_or_create(value: 'Acme Desk').update!(value: 'Acme Desk')
    GlobalConfig.clear_cache
    invalid_rule = account.automation_rules.new(name: 'x', event_name: 'conversation_created', actions: [],
                                                conditions: [condition('equal_to', [shared.id])])

    with_modified_env LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED: 'false' do
      invalid_rule.valid?
    end

    expect(invalid_rule.errors[:conditions].join).to include('Acme Desk')
  end
end
