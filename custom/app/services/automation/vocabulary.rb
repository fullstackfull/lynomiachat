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
    'contact_audience' => 'audiences', 'commerce_store' => 'stores',
    # The EVENT's store, which is a different key from the contact's but takes the same values.
    # LynomiaCondition#event_errors runs them through own_stores?, which wants integer ids of this
    # account's own stores -- so without this binding a client renders a free-text box and every
    # value a merchant could type into it comes back `invalid_store`.
    'commerce_event_store' => 'stores'
  }.freeze

  # WHAT A CUSTOM ATTRIBUTE'S DISPLAY TYPE MEANS FOR ITS OPERATORS.
  #
  # Unlike every other entry here this one cannot be read off the server, because the server does not
  # decide it: AutomationRules::ConditionValidationService takes the custom-attribute branch, checks only
  # that the attribute EXISTS, and accepts whatever operator it was given. The set that is really offered
  # is the dashboard's, in app/javascript/dashboard/helper/automationHelper.js (getOperatorTypes) reading
  # the sets in .../settings/automation/operators.js -- and a second client serving fewer than those is
  # the capability reduction this vocabulary exists to prevent, not a safe conservative default.
  #
  # So it is mirrored here rather than derived, and spec/services/automation/vocabulary_spec.rb reads
  # those two JavaScript files and fails if they ever stop agreeing. A mirror with no check is the drift.
  OPERATOR_TYPES_1 = %w[equal_to not_equal_to].freeze
  OPERATOR_TYPES_3 = (OPERATOR_TYPES_1 + %w[is_present is_not_present]).freeze
  OPERATOR_TYPES_4 = (OPERATOR_TYPES_3 + %w[is_greater_than is_less_than]).freeze
  CUSTOM_OPERATORS = Hash.new(OPERATOR_TYPES_1).merge('text' => OPERATOR_TYPES_3, 'date' => OPERATOR_TYPES_4).freeze

  # C: the Lynomia keys' own types, which are not all text. An operator set is only half of what a client
  # needs to draw an input: `commerce_orders_count` compared with is_greater_than wants a number field,
  # `commerce_last_purchase_at` a date one, and `commerce_active_order` a yes/no rather than a text box a
  # merchant can type "maybe" into. Declaring them all text made three of them unusable in practice.
  DATA_TYPES = { 'commerce_orders_count' => 'number', 'commerce_last_purchase_at' => 'date',
                 'commerce_active_order' => 'boolean' }.freeze

  module_function

  def conditions(account)
    standard + custom(account) + lynomia(account)
  end

  # The triggers this installation can run and the actions it can take, from the rule's own allow-lists -- the
  # same ones that refuse a rule naming anything else.
  #
  # EACH TRIGGER SAYS WHETHER IT CAN ACTUALLY FIRE FOR THIS ACCOUNT, and that is not decoration. A Commerce
  # trigger is a valid name for every account -- AutomationRule#event_names lists them unconditionally and a
  # rule naming one SAVES -- but it only ever fires where Commerce is on, a store is connected, and, for the
  # cart trigger, that store's provider has cleared UAT and has recovery switched on. A client offering the
  # cart trigger to a merchant whose provider is still PRE_UAT offers a rule that looks created and does
  # nothing, which is the failure mode this whole vocabulary exists to prevent.
  #
  # `reason` IS A CODE, NOT A SENTENCE, like everything else here: the client writes the words.
  # BOTH BLOCKER LOOKUPS ARE RESOLVED ONCE FOR THE WHOLE LIST, not once per event name. Each is remote --
  # `Automation::Extensions.enabled?` is a Redis read and both store checks are queries -- and neither can
  # answer differently for two names in the same response, so asking per name was eight identical round
  # trips on an endpoint the Studio calls on every page load.
  def events(account)
    commerce = commerce_blocker(account)
    cart = commerce || recovery_blocker(account)

    AutomationRule.new(account: account).event_names.map do |name|
      reason = event_reason(name, commerce, cart)
      { name: name, available: reason.nil?, reason: reason }.compact
    end
  end

  # Why a trigger cannot fire for this account, or nil when it can.
  def event_blocker(account, name)
    return nil unless Automation::CommerceEvents.event?(name)

    event_reason(name, commerce_blocker(account), cart_blocker(account, name))
  end

  def event_reason(name, commerce, cart)
    return nil unless Automation::CommerceEvents.event?(name)

    Automation::CommerceEvents::CART_EVENTS.include?(name) ? cart : commerce
  end

  def commerce_blocker(account)
    return 'extensions_disabled' unless Automation::Extensions.enabled?
    return 'commerce_disabled' unless account.feature_enabled?('lynomia_commerce')

    'no_store' if account.commerce_stores.connected.empty?
  end

  def cart_blocker(account, name)
    return nil unless Automation::CommerceEvents::CART_EVENTS.include?(name)

    commerce_blocker(account) || recovery_blocker(account)
  end

  # The cart trigger needs a provider whose abandoned carts are actually collected: a provider still in PRE_UAT
  # never produces one, whatever the switch says.
  def recovery_blocker(account)
    collected = account.commerce_stores.connected.any? { |store| Commerce::Switches.provider_recovery_enabled?(store.provider) }
    'recovery_unavailable' unless collected
  end

  # Each action with the shape of what it takes; see Automation::ActionFields for why an action with no
  # `fields` entry is one a client must not offer.
  def actions(account)
    AutomationRule.new(account: account).actions_attributes.map do |name|
      { name: name, fields: Automation::ActionFields::FOR[name],
        commerce_safe: Custom::AutomationRule::CUSTOMER_MESSAGE_ACTIONS.exclude?(name) }.compact
    end
  end

  # ONE ENTRY PER KEY, RESOLVED THE WAY THE VALIDATOR RESOLVES IT.
  #
  # `labels`, `created_at` and `last_activity_at` are each defined under BOTH conversations and contacts,
  # with the same data type and the same operators and only the scope differing. Served twice, a client is
  # told there is a contact `created_at` it can filter on separately -- and there is not:
  # ConditionValidationService looks up `@conversation_filters[key] || @contact_filters[key] || ...`, so a
  # condition on any of the three is ALWAYS evaluated as the conversation one. Offering the contact copy
  # is offering a capability that silently becomes a different one. First definition wins, in SCOPES order,
  # which is that same conversation-first order.
  def standard
    entries = SCOPES.flat_map do |group, scope|
      FILTER_KEYS.fetch(group).map { |key, filter| entry(key, scope, filter['data_type'], filter['filter_operators']) }
    end

    entries.uniq { |condition| condition[:key] }
  end

  def custom(account)
    account.custom_attribute_definitions.map do |definition|
      entry(definition.attribute_key, definition.attribute_model, definition.attribute_display_type,
            CUSTOM_OPERATORS[definition.attribute_display_type])
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
      entry(key, lynomia_scope(key), DATA_TYPES.fetch(key, 'text'), condition.operators)
        .merge(available: condition.available?)
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
