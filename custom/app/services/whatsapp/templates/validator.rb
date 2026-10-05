# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/01-meta-api-contract.md section 2): the rules Meta
# publishes, checked here so a mistake costs a keystroke instead of a review cycle. Every problem is returned as
# { field:, code:, limit: } so the builder can point at the input that is wrong, and the codes are stable so the copy
# lives in i18n rather than in a sentence built on the server.
#
# This is the authority for both layers that matter: the builder shows what it returns, and a submit refuses on it.
# Meta stays the final word -- it rejects for reasons no public rule covers -- so nothing here claims a template will
# be approved.
class Whatsapp::Templates::Validator
  HEADER_TEXT_MAX = 60
  BODY_MAX = 1024
  FOOTER_MAX = 60
  BUTTON_TEXT_MAX = 25
  BUTTON_URL_MAX = 2000
  BUTTON_PHONE_MAX = 20
  # Meta raised the coupon code from 15 to 20 on 2025-12-03. Whatsapp::PopulateTemplateParametersService still refuses
  # anything over 15 at SEND time, so a template authored up to 20 can be created at Meta and would fail to send with
  # a longer code; the manager therefore holds the stricter of the two until that send-path constant is raised.
  BUTTON_COPY_CODE_MAX = 15
  BUTTONS_MAX = 10
  BUTTON_TYPE_MAX = { 'QUICK_REPLY' => 10, 'URL' => 2, 'PHONE_NUMBER' => 1, 'COPY_CODE' => 1 }.freeze

  SUPPORTED_COMPONENTS = %w[HEADER BODY FOOTER BUTTONS].freeze
  SUPPORTED_HEADER_FORMATS = %w[TEXT IMAGE VIDEO DOCUMENT].freeze
  SUPPORTED_BUTTON_TYPES = %w[QUICK_REPLY URL PHONE_NUMBER COPY_CODE].freeze
  VARIABLE = /\{\{([^}]*)\}\}/
  NAMED_VARIABLE = /\A[a-z][a-z0-9_]*\z/

  def initialize(template)
    @template = template
    @problems = []
  end

  def problems
    @problems = []
    check_identity
    check_components
    @problems
  end

  def valid?
    problems.empty?
  end

  private

  attr_reader :template

  def add(field, code, limit = nil)
    @problems << { field: field, code: code, limit: limit }.compact
  end

  def components
    @components ||= Array(template.components).select { |component| component.is_a?(Hash) }
  end

  def component(type)
    components.find { |candidate| candidate['type'].to_s.upcase == type }
  end

  def named?
    template.parameter_format.to_s.upcase == 'NAMED'
  end

  def check_identity
    add('name', 'name_format') unless template.name.to_s.match?(Whatsapp::MessageTemplate::NAME_FORMAT)
    add('language', 'language_blank') if template.language.blank?
    add('category', 'category_unsupported') unless Whatsapp::MessageTemplate::CATEGORIES.include?(template.category.to_s)
    return if Whatsapp::MessageTemplate::PARAMETER_FORMATS.include?(template.parameter_format.to_s.upcase)

    add('parameter_format', 'parameter_format_unsupported')
  end

  def check_components
    check_component_set
    check_body
    check_header
    check_footer
    check_buttons
  end

  def check_component_set
    seen = components.map { |component| component['type'].to_s.upcase }
    seen.each { |type| add('components', 'component_unsupported') if SUPPORTED_COMPONENTS.exclude?(type) }
    seen.tally.each { |type, count| add(type.downcase, 'component_duplicated') if count > 1 }
  end

  def check_body
    body = component('BODY')
    return add('body', 'body_missing') if body.nil?

    text = body['text'].to_s
    return add('body', 'body_blank') if text.strip.empty?

    add('body', 'body_too_long', BODY_MAX) if text.length > BODY_MAX
    check_variables('body', text)
    check_examples('body', text, body['example'], positional_key: 'body_text', named_key: 'body_text_named_params')
  end

  def check_header
    header = component('HEADER')
    return if header.nil?

    format = header['format'].to_s.upcase
    return add('header', 'header_format_unsupported') if SUPPORTED_HEADER_FORMATS.exclude?(format)
    return check_media_header(header) unless format == 'TEXT'

    text = header['text'].to_s
    add('header', 'header_too_long', HEADER_TEXT_MAX) if text.length > HEADER_TEXT_MAX
    add('header', 'header_too_many_variables', 1) if variables(text).length > 1
    check_variables('header', text)
    check_examples('header', text, header['example'], positional_key: 'header_text',
                                                      named_key: 'header_text_named_params')
  end

  def check_media_header(header)
    return if header.dig('example', 'header_handle').present?

    add('header', 'header_example_missing')
  end

  def check_footer
    footer = component('FOOTER')
    return if footer.nil?

    text = footer['text'].to_s
    add('footer', 'footer_too_long', FOOTER_MAX) if text.length > FOOTER_MAX
    # Meta allows no variables in a footer at all.
    add('footer', 'footer_has_variables') if variables(text).any?
  end

  def check_buttons
    buttons = Array(component('BUTTONS')&.dig('buttons')).select { |button| button.is_a?(Hash) }
    return if buttons.empty?

    add('buttons', 'buttons_too_many', BUTTONS_MAX) if buttons.length > BUTTONS_MAX
    check_button_types(buttons)
    check_quick_reply_grouping(buttons)
    buttons.each_with_index { |button, index| check_button(button, index) }
  end

  def check_button_types(buttons)
    buttons.map { |button| button['type'].to_s.upcase }.tally.each do |type, count|
      next add('buttons', 'button_type_unsupported') if SUPPORTED_BUTTON_TYPES.exclude?(type)

      maximum = BUTTON_TYPE_MAX[type]
      add('buttons', 'button_type_too_many', maximum) if maximum && count > maximum
    end
  end

  # Meta: quick replies and other buttons must form two groups. [QR, URL, QR] is refused even though every per-type
  # maximum is respected, so the order matters, not just the count.
  def check_quick_reply_grouping(buttons)
    quick = buttons.each_index.select { |index| buttons[index]['type'].to_s.upcase == 'QUICK_REPLY' }
    return if quick.length < 2

    add('buttons', 'buttons_quick_reply_not_grouped') unless quick.last - quick.first == quick.length - 1
  end

  def check_button(button, index)
    field = "buttons.#{index}"
    type = button['type'].to_s.upcase
    add(field, 'button_text_too_long', BUTTON_TEXT_MAX) if button['text'].to_s.length > BUTTON_TEXT_MAX
    case type
    when 'URL' then check_url_button(button, field)
    when 'PHONE_NUMBER'
      add(field, 'button_phone_too_long', BUTTON_PHONE_MAX) if button['phone_number'].to_s.length > BUTTON_PHONE_MAX
    when 'COPY_CODE' then check_copy_code_button(button, field)
    end
  end

  def check_url_button(button, field)
    url = button['url'].to_s
    add(field, 'button_url_blank') if url.strip.empty?
    add(field, 'button_url_too_long', BUTTON_URL_MAX) if url.length > BUTTON_URL_MAX
    check_url_variable(url, button, field)
  end

  # Meta supports one variable in a URL button, appended to the end of the string, with a sample value.
  def check_url_variable(url, button, field)
    count = variables(url).length
    return if count.zero?

    add(field, 'button_url_too_many_variables', 1) if count > 1
    add(field, 'button_url_variable_not_at_end') unless url.end_with?('}}')
    add(field, 'button_example_missing') if Array(button['example']).compact_blank.empty?
  end

  def check_copy_code_button(button, field)
    example = button['example']
    return add(field, 'button_example_missing') if example.blank?

    add(field, 'button_copy_code_too_long', BUTTON_COPY_CODE_MAX) if example.to_s.length > BUTTON_COPY_CODE_MAX
  end

  def variables(text)
    text.to_s.scan(VARIABLE).flatten.map(&:strip)
  end

  # The placement rules Meta rejects on, each costing a review cycle: a dangling placeholder at either end, two
  # placeholders with nothing between them, positional keys that do not run 1..n, and named keys that are not unique
  # lowercase words.
  def check_variables(field, text)
    keys = variables(text)
    return if keys.empty?

    stripped = text.strip
    add(field, 'variable_at_edge') if stripped.start_with?('{{') || stripped.end_with?('}}')
    add(field, 'variables_adjacent') if text.match?(/\}\}\s*\{\{/)
    named? ? check_named_variables(field, keys) : check_positional_variables(field, keys)
  end

  def check_named_variables(field, keys)
    add(field, 'variable_name_invalid') unless keys.all? { |key| key.match?(NAMED_VARIABLE) }
    add(field, 'variable_duplicated') if keys.uniq.length != keys.length
  end

  def check_positional_variables(field, keys)
    return add(field, 'variable_name_invalid') unless keys.all? { |key| key.match?(/\A[1-9]\d*\z/) }

    add(field, 'variables_not_sequential') unless keys.map(&:to_i) == (1..keys.length).to_a
  end

  # Meta requires a sample value for every variable at create time, and the key depends on the parameter format.
  def check_examples(field, text, example, positional_key:, named_key:)
    keys = variables(text)
    return if keys.empty?

    given = named? ? named_examples(example, named_key) : positional_examples(example, positional_key)
    add(field, 'variable_example_missing') if given.length < keys.length
  end

  def named_examples(example, key)
    Array(example&.dig(key)).select { |entry| entry.is_a?(Hash) && entry['example'].present? }
  end

  def positional_examples(example, key)
    values = example&.dig(key)
    # body_text is an array of arrays; header_text is flat.
    values = values.first if values.is_a?(Array) && values.first.is_a?(Array)
    Array(values).compact_blank
  end
end
