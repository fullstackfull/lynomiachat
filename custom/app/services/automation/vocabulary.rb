# frozen_string_literal: true

# WHAT AN AUTOMATION OR A FLOW CONDITION MAY SAY, served so a client does not have to know.
#
# WHY. Lynomia's own dashboard carries this vocabulary as JavaScript constants, maintained beside the server's and
# kept in step by hand. The Phase 4A capability review named that as a trap rather than a precedent: a second
# client -- the Store Syria Automation Studio -- copying those constants would offer a merchant an attribute the
# server rejects, or withhold one it accepts, and either way the merchant finds out when their rule or flow
# refuses to save. There is one vocabulary, it lives on the server, and this serves it.
#
# THREE SOURCES, EACH READ WHERE IT IS DEFINED AND NOWHERE ELSE:
#
#   lib/filters/filter_keys.yml       the standard conversation, contact and message attributes and their
#                                     operators -- the same file AutomationRules::ConditionValidationService
#                                     validates against, so an offered operator is an accepted one
#   the account's own definitions     its custom attributes, which are per account and cannot be a constant
#   Automation::LynomiaCondition      the audience and Commerce keys this fork adds, with `available` saying
#                                     whether THIS account may use them rather than hiding them -- a merchant
#                                     who cannot use Commerce conditions should see why, not wonder where they are
#
# `options_from` IS A BINDING, NOT A LIST. A key whose values are ids -- an agent, a team, an inbox, a store --
# names the reference collection its picker reads, because those are per account and already served. A key whose
# values are a fixed enum carries them inline, read from the model's own enum so a new status appears here the
# day it appears there.
#
# NO HUMAN TEXT. No label and no hint: the words belong to the client, in the merchant's own language.
module Automation::Vocabulary
  FILTER_KEYS = YAML.safe_load(Rails.root.join('lib/filters/filter_keys.yml').read).freeze
  SCOPES = { 'conversations' => 'conversation', 'contacts' => 'contact', 'messages' => 'message' }.freeze

  # Keys whose values are this account's own records, named rather than listed.
  OPTIONS_FROM = {
    'assignee_id' => 'agents', 'team_id' => 'teams', 'inbox_id' => 'inboxes', 'labels' => 'labels',
    'contact_audience' => 'audiences', 'commerce_store' => 'stores'
  }.freeze

  module_function

  def conditions(account)
    standard + custom(account) + lynomia(account)
  end

  # The triggers this installation can actually run and the actions it can actually take, from the rule's own
  # allow-lists -- the same ones that refuse a rule naming anything else.
  def events(account) = AutomationRule.new(account: account).event_names

  def actions(account) = AutomationRule.new(account: account).actions_attributes

  def standard
    SCOPES.flat_map do |group, scope|
      FILTER_KEYS.fetch(group).map do |key, filter|
        entry(key, scope, filter['data_type'], filter['filter_operators'])
      end
    end
  end

  def custom(account)
    account.custom_attribute_definitions.map do |definition|
      entry(definition.attribute_key, definition.attribute_model, definition.attribute_display_type,
            FILTER_KEYS.dig('conversations', 'status', 'filter_operators'))
        .merge(custom_attribute: true)
    end
  end

  def lynomia(account)
    keys = [Automation::LynomiaCondition::AUDIENCE_KEY] + Automation::LynomiaCondition::EVENT_KEYS +
           Audience::CommerceCondition::FIELDS.keys

    keys.map do |key|
      condition = Automation::LynomiaCondition.new(key, account: account)
      # `available` per key, never once for the group: an audience condition needs only the extensions switch
      # while a Commerce one also needs Commerce, and reporting them together marks one of the two wrongly.
      entry(key, lynomia_scope(key), 'text', condition.operators).merge(available: condition.available?)
    end
  end

  # THE ONE CONDITION FAMILY THAT IS NOT A FIXED KEY. Spend is per currency and never converted
  # (`commerce_spend_sar`), so the set of real keys depends on what a store has sold in. Described as a pattern
  # rather than listed, because listing it would mean either guessing at currencies or omitting the family --
  # and omitting it silently is how a client decides a capability does not exist.
  def patterns(account)
    [{ prefix: 'commerce_spend_', suffix: 'currency', scope: 'commerce', data_type: 'number',
       operators: Audience::CommerceCondition::SPEND_OPERATORS,
       available: Automation::LynomiaCondition.new('commerce_orders_count', account: account).available? }]
  end

  def lynomia_scope(key)
    return 'audience' if key == Automation::LynomiaCondition::AUDIENCE_KEY

    Automation::LynomiaCondition.event_key?(key) ? 'commerce_event' : 'commerce'
  end

  def entry(key, scope, data_type, operators)
    { key: key, scope: scope, data_type: data_type, operators: Array(operators),
      options_from: OPTIONS_FROM[key], values: values_for(key) }.compact
  end

  # Enumerated values read from the model's own enum, so a status added there appears here in the same deploy.
  def values_for(key)
    case key
    when 'status' then Conversation.statuses.keys
    when 'priority' then Conversation.priorities.keys
    when 'message_type' then Message.message_types.keys
    when 'commerce_provider', 'commerce_event_provider' then Commerce::Providers.enabled
    else Audience::CommerceCondition::STATUSES.dig(key, 1)
    end
  end
end
