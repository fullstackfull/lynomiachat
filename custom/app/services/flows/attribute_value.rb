# A value a flow writes into a contact or conversation custom attribute, checked against the account's
# CustomAttributeDefinition (docs/flow-builder/04-node-contracts.md §attributes): its type, its list values, its regex.
# The regex is the definition's own (`/pattern/flags`, as the dashboard stores it), compiled with a time limit so a
# pattern can never stall a worker. Returns the value to store, or nil when it does not fit.
module Flows::AttributeValue
  REGEX_TIMEOUT = 0.1
  TRUE_WORDS = %w[true yes 1].freeze
  FALSE_WORDS = %w[false no 0].freeze

  CASTS = { 'number' => :number, 'currency' => :number, 'percent' => :number, 'checkbox' => :checkbox, 'list' => :list_value,
            'date' => :date, 'link' => :link }.freeze

  def self.cast(definition, raw)
    value = raw.to_s.strip
    return nil if value.empty? || !matches_regex?(definition, value)

    caster = CASTS[definition.attribute_display_type]
    caster ? send(caster, value, definition) : value.first(1024)
  end

  def self.number(value, _definition)
    Float(Flows::Reply.latin_digits(value).tr(',', '.')).then { |number| number == number.to_i ? number.to_i : number }
  rescue ArgumentError
    nil
  end

  def self.checkbox(value, _definition)
    word = value.downcase
    return true if TRUE_WORDS.include?(word)

    FALSE_WORDS.include?(word) ? false : nil
  end

  def self.list_value(value, definition) = Array(definition.attribute_values).find { |option| option.to_s.casecmp?(value) }

  def self.date(value, _definition)
    Date.iso8601(value).iso8601
  rescue Date::Error
    nil
  end

  def self.link(value, _definition) = value.match?(%r{\Ahttps?://\S+\z}) ? value : nil

  def self.matches_regex?(definition, value)
    pattern = definition.regex_pattern.presence
    return true if pattern.nil?

    regex(pattern)&.match?(value) || false
  rescue Regexp::TimeoutError
    false
  end

  def self.regex(pattern)
    last = pattern.rindex('/')
    source, flags = pattern.start_with?('/') && last.positive? ? [pattern[1...last], pattern[(last + 1)..]] : [pattern, '']
    options = (flags.include?('i') ? Regexp::IGNORECASE : 0) | (flags.include?('m') ? Regexp::MULTILINE : 0)
    Regexp.new(source, options, timeout: REGEX_TIMEOUT)
  rescue RegexpError
    nil
  end

  private_class_method :number, :checkbox, :list_value, :date, :link, :matches_regex?, :regex
end
