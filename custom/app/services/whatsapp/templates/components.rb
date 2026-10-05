# Lynomia WhatsApp Template Manager: narrows a client's components to the documented Meta shape before anything is
# stored or sent (docs/whatsapp-template-manager/01-meta-api-contract.md section 2). Only the keys Meta documents for
# the four components this phase authors survive, so the jsonb column cannot accumulate junk and nothing undocumented
# reaches Graph. A component or key that is not in the allow-list is dropped here and reported by
# Whatsapp::Templates::Validator, which sees the sanitised set.
class Whatsapp::Templates::Components
  KEYS = {
    'HEADER' => %w[type format text example],
    'BODY' => %w[type text example],
    'FOOTER' => %w[type text],
    'BUTTONS' => %w[type buttons]
  }.freeze
  EXAMPLE_KEYS = %w[header_text header_text_named_params header_handle body_text body_text_named_params].freeze
  BUTTON_KEYS = %w[type text url phone_number example].freeze

  def self.sanitize(raw)
    Array(raw).filter_map { |component| new(component).sanitized }
  end

  def initialize(component)
    @component = component.respond_to?(:to_unsafe_h) ? component.to_unsafe_h : component
    @component = @component.is_a?(Hash) ? @component.deep_stringify_keys : {}
  end

  def sanitized
    type = @component['type'].to_s.upcase
    allowed = KEYS[type]
    return if allowed.nil?

    sanitized = @component.slice(*allowed).merge('type' => type)
    sanitized['example'] = sanitize_example(sanitized['example']) if sanitized.key?('example')
    sanitized['buttons'] = sanitize_buttons(sanitized['buttons']) if sanitized.key?('buttons')
    sanitized.compact
  end

  private

  def sanitize_example(example)
    return nil unless example.is_a?(Hash)

    example.slice(*EXAMPLE_KEYS).presence
  end

  def sanitize_buttons(buttons)
    Array(buttons).filter_map do |button|
      button = button.to_unsafe_h if button.respond_to?(:to_unsafe_h)
      next unless button.is_a?(Hash)

      button.deep_stringify_keys.slice(*BUTTON_KEYS)
            .merge('type' => button.deep_stringify_keys['type'].to_s.upcase).compact
    end
  end
end
