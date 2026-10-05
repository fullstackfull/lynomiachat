# Lynomia WhatsApp Template Manager: the three template calls the Graph client did not have -- create, edit and
# delete. It is the same client, extended, so the base URL, the configured API version and the bearer header all come
# from Whatsapp::FacebookApiClient; no second client and no hand-rolled protocol code.
#
# Unlike its parent these raise a structured TemplateApiError rather than a string, because the manager has to turn
# Meta's refusal into something a person can act on while the full body goes only to the log
# (docs/whatsapp-template-manager/01-meta-api-contract.md).
class Whatsapp::Templates::MetaClient < Whatsapp::FacebookApiClient
  class TemplateApiError < StandardError
    attr_reader :status, :error

    def initialize(status, body)
      @status = status
      @error = (body.is_a?(Hash) ? body['error'] : nil) || {}
      super("WhatsApp template request failed (#{status}): #{@error['message'] || body}")
    end

    def code = @error['code']
    def subcode = @error['error_subcode']
    # Meta writes these two for an end user to read, so they are the only part of a Graph error worth showing.
    def user_message = @error['error_user_msg'].presence || @error['error_user_title'].presence
    def trace_id = @error['fbtrace_id']
  end

  # POST /{WABA_ID}/message_templates. `allow_category_change` is deliberately absent: Meta stopped supporting it on
  # 2025-04-09 and the behaviour it enabled is now the default. The response carries the id, the status and the
  # category Meta actually assigned, which can differ from the one submitted.
  def create_template(waba_id, payload)
    post_template("#{waba_id}/message_templates", payload)
  end

  # POST /{TEMPLATE_ID}. Meta replaces ALL components with the ones sent, so the caller must send the complete set,
  # and the response is only { success: true } -- never a status.
  def edit_template(template_id, payload)
    post_template(template_id.to_s, payload)
  end

  # DELETE /{WABA_ID}/message_templates. The documented single-template shape is hsm_id WITH the name; a name on its
  # own deletes every language of that name.
  def delete_template(waba_id, name:, hsm_id: nil)
    response = HTTParty.delete(
      template_url("#{waba_id}/message_templates"),
      headers: request_headers,
      query: { name: name, hsm_id: hsm_id }.compact
    )

    handle(response)
  end

  private

  def post_template(path, payload)
    handle(HTTParty.post(template_url(path), headers: request_headers, body: payload.to_json))
  end

  def template_url(path)
    "#{BASE_URI}/#{@api_version}/#{path}"
  end

  def handle(response)
    raise TemplateApiError.new(response.code, response.parsed_response) unless response.success?

    response.parsed_response
  end
end
