# One node's `data` checked against its contract and the account (docs/flow-builder/04-node-contracts.md): every id it
# names (label, team, agent, attribute, shared audience, store) must be this account's, every text within the channel's
# limits, every variable on the allow-list. Conditions are checked by Lynomia Automation's own rule validation: a
# condition node holds Automation conditions and nothing else.
class Flows::NodeValidator
  CAPS = Flows::ChannelCapabilities::WHATSAPP
  REPLY_TYPES = %w[any number email phone keywords].freeze
  PRIORITIES = %w[low medium high urgent].freeze
  LOOKUP_MODES = %w[latest_order order_number].freeze
  MAX_TIMEOUT_MINUTES = 1440
  MAX_DELAY_SECONDS = 86_400
  MAX_CONDITIONS = 10
  STORE_MODELS = { 'contact' => 'contact_attribute', 'conversation' => 'conversation_attribute' }.freeze

  def initialize(account, node)
    @account = account
    @node = node
    @data = node['data'].is_a?(Hash) ? node['data'] : {}
    @errors = []
  end

  def errors
    check_keys
    send("check_#{@node['type']}")
    @errors
  end

  private

  def add(code, detail = nil) = @errors << { code: code, node_id: @node['id'], detail: detail }.compact

  def check_keys
    extra = @data.keys - Flows::NodeTypes.data_keys(@node['type'])
    add('unknown_field', extra.join(', ')) if extra.any?
  end

  def check_start
    check_words(@data['keywords']) if @data.key?('keywords')
    check_conditions(@data['conditions'], allow_empty: true) if @data.key?('conditions')
  end

  def check_send_message = check_text(@data['text'], CAPS[:text][:body])

  def check_question
    check_text(@data['text'], CAPS[:text][:body])
    check_reply_rules
    check_store(@data['store_as']) if @data['store_as'].present?
    check_text(@data['retry_text'], CAPS[:text][:body]) if @data['retry_text'].present?
    check_timeout
  end

  def check_reply_rules
    add('invalid_reply_type') unless REPLY_TYPES.include?(@data['reply_type'] || 'any')
    check_words(@data['keywords'], required: true) if @data['reply_type'] == 'keywords'
    add('invalid_attempts') unless (1..5).cover?(Integer(@data['max_attempts'] || 3, exception: false))
  end

  def check_buttons = check_choices(CAPS[:buttons])

  def check_list
    check_choices(CAPS[:list])
    add('button_label_too_long', CAPS[:list][:button]) if @data['button_label'].to_s.length > CAPS[:list][:button]
  end

  def check_choices(limits)
    check_text(@data['text'], limits[:body])
    options = Array(@data['options'])
    return add('invalid_options') unless options.size.between?(1, limits[:max]) && options.all?(Hash)

    add('invalid_options') unless option_ids?(options)
    options.each { |option| check_option(option, limits) }
    check_timeout
  end

  def option_ids?(options)
    ids = options.map { |option| option['id'].to_s }
    ids.all? { |id| Flows::NodeTypes::ID.match?(id) } && ids.uniq.size == ids.size
  end

  def check_option(option, limits)
    add('option_title', option['id']) unless option['title'].to_s.strip.length.between?(1, limits[:title])
    add('option_description', option['id']) if option['description'].to_s.length > limits[:description].to_i
  end

  def check_condition = check_conditions(@data['conditions'])

  def check_audience_condition = check_conditions(@data['conditions'], only: ->(key) { key == 'contact_audience' })

  def check_commerce_condition
    return add('commerce_disabled') unless commerce?

    check_conditions(@data['conditions'], only: ->(key) { key.start_with?('commerce_') })
  end

  def check_set_contact_attribute = check_attribute('contact_attribute')

  def check_set_conversation_attribute = check_attribute('conversation_attribute')

  def check_add_label = check_labels(@data['labels'], required: true)

  def check_remove_label = check_labels(@data['labels'], required: true)

  def check_assign_agent = check_agent(@data['agent_id'], required: true)

  def check_assign_team = check_team(@data['team_id'], required: true)

  def check_commerce_lookup
    add('commerce_disabled') unless commerce?
    add('invalid_mode') unless LOOKUP_MODES.include?(@data['mode'])
    return if @data['number'].blank?

    add('invalid_number') unless @data['mode'] == 'order_number' && @data['number'].to_s.length <= 64
    unknown = Flows::Variables.unknown(@data['number'], flow_only: true)
    add('unknown_variable', unknown.join(', ')) if unknown.any?
  end

  def check_webhook
    uri = URI.parse(@data['url'].to_s)
    add('invalid_url') unless uri.is_a?(URI::HTTP) && uri.host.present? && @data['url'].length <= Limits::URL_LENGTH_LIMIT
  rescue URI::InvalidURIError
    add('invalid_url')
  end

  def check_delay
    add('invalid_delay') unless (1..MAX_DELAY_SECONDS).cover?(Integer(@data['seconds'].to_s, exception: false))
  end

  def check_handoff
    check_team(@data['team_id']) if @data['team_id'].present?
    check_agent(@data['agent_id']) if @data['agent_id'].present?
    add('invalid_priority') if @data['priority'].present? && PRIORITIES.exclude?(@data['priority'])
    check_labels(@data['labels']) if @data['labels'].present?
    add('reason_too_long') if @data['reason'].to_s.length > 255
  end

  def check_goto
    add('invalid_target') unless @data['target'].is_a?(String) && @data['target'] != @node['id']
  end

  def check_end
    add('invalid_resolve') unless [nil, true, false].include?(@data['resolve'])
  end

  def check_text(text, max)
    return add('text_required') if text.to_s.strip.empty?
    return add('text_too_long', max) if text.to_s.length > max

    unknown = Flows::Variables.unknown(text)
    add('unknown_variable', unknown.join(', ')) if unknown.any?
  end

  def check_words(words, required: false)
    words = Array(words)
    return add('keywords_required') if required && words.empty?

    add('invalid_keywords') unless words.size <= 20 && words.all? { |word| word.is_a?(String) && word.strip.length.between?(1, 64) }
  end

  def check_timeout
    return if @data['timeout_minutes'].blank?

    add('invalid_timeout') unless (1..MAX_TIMEOUT_MINUTES).cover?(Integer(@data['timeout_minutes'].to_s, exception: false))
  end

  def check_store(store)
    return add('invalid_store') unless store.is_a?(Hash)
    return check_context_key(store['key']) if store['scope'] == 'context'
    return add('invalid_store') unless STORE_MODELS.key?(store['scope'])

    definition(STORE_MODELS[store['scope']], store['key']) || add('unknown_attribute', store['key'])
  end

  def check_context_key(key)
    add('invalid_store') unless Flows::Variables::CONTEXT_KEY.match?(key.to_s) && Flows::Variables::RESERVED.exclude?(key)
  end

  def check_attribute(model)
    found = definition(model, @data['key'])
    return add('unknown_attribute', @data['key']) unless found

    value = @data['value'].to_s
    return add('text_required') if value.strip.empty?
    return add('text_too_long', 1024) if value.length > 1024

    unknown = Flows::Variables.unknown(value, flow_only: true)
    return add('unknown_variable', unknown.join(', ')) if unknown.any?

    add('invalid_attribute_value', @data['key']) if value.exclude?('{{') && Flows::AttributeValue.cast(found, value).nil?
  end

  def check_labels(labels, required: false)
    labels = Array(labels)
    return add('labels_required') if required && labels.empty?
    return add('invalid_labels') unless labels.size <= 10 && labels.all?(String)

    missing = labels - @account.labels.where(title: labels).pluck(:title)
    add('unknown_label', missing.join(', ')) if missing.any?
  end

  def check_team(id, required: false)
    return add('team_required') if required && id.blank?

    add('unknown_team', id.to_s) unless @account.teams.exists?(id: Integer(id.to_s, exception: false))
  end

  def check_agent(id, required: false)
    return add('agent_required') if required && id.blank?

    add('unknown_agent', id.to_s) unless @account.users.exists?(id: Integer(id.to_s, exception: false))
  end

  # Conditions as Lynomia Automation validates them, in a rule that is never saved.
  def check_conditions(conditions, allow_empty: false, only: nil)
    conditions = Array(conditions)
    return if allow_empty && conditions.empty?

    problem = conditions_problem(conditions, only)
    return add(*problem) if problem

    rule = Flows::ConditionRule.build(@account, conditions)
    rule.validate
    add('invalid_conditions', rule.errors[:conditions].join(' ')) if rule.errors[:conditions].any?
  end

  def conditions_problem(conditions, only)
    return ['conditions_required'] if conditions.empty?
    return ['too_many_conditions', MAX_CONDITIONS] if conditions.size > MAX_CONDITIONS
    return ['invalid_conditions'] unless conditions.all?(Hash)

    keys_problem(conditions.map { |condition| condition['attribute_key'].to_s }, only) ||
      (%w[condition_not_allowed attribute_changed] if conditions.pluck('filter_operator').include?('attribute_changed'))
  end

  def keys_problem(keys, only) = (['condition_not_allowed', keys.join(', ')] if only && !keys.all?(only))

  def definition(model, key)
    key.present? && @account.custom_attribute_definitions.find_by(attribute_model: model, attribute_key: key)
  end

  def commerce? = @account.feature_enabled?('lynomia_commerce')
end
