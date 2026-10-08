# Lynomia Flow Builder (docs/flow-builder/06-whatsapp-channel-capabilities.md): a flow's List node is always sent as a
# WhatsApp list (Chatwoot chooses buttons for three items or fewer without descriptions) and may name the list's button.
# Every other input_select message is sent as before.
module Custom::Whatsapp::Providers::BaseService
  LIST_BUTTON_MAX = 20

  # Lynomia Campaigns (docs/campaigns/02-recipients.md): a failed campaign recipient carries Meta's own
  # wording, which only exists on the provider response. The provider instance is kept by
  # Custom::Channel::Whatsapp#send_template so the caller can read it after the send.
  attr_reader :last_error

  def process_response(response, message)
    @last_error = nil
    super
  end

  def handle_error(response, message)
    @last_error = parsed_error(response)
    super
  end

  def create_payload_based_on_items(message)
    return super unless message.content_attributes['interactive_type'] == 'list'

    create_list_payload(message)
  end

  def create_list_payload(message)
    payload = super
    label = message.content_attributes['list_button'].to_s.strip.first(LIST_BUTTON_MAX)
    return payload if label.empty?

    payload.merge(action: JSON.generate(JSON.parse(payload[:action]).merge('button' => label)))
  end

  private

  def parsed_error(response)
    parsed_response = response.parsed_response
    error = parsed_response.is_a?(Hash) ? parsed_response['error'] || {} : {}
    {
      code: error['code'],
      title: error['error_user_title'].presence || error['title'],
      message: error['error_user_msg'].presence || error.dig('error_data', 'details').presence || error['message'].presence
    }.compact_blank.presence
  end
end
