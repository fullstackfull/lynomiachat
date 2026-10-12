# The text one contact actually received (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md §3).
#
# A WhatsApp campaign does not send free text: it sends an approved template plus this contact's values for the
# template's variables. So the message the operator is looking at in the recipient list exists nowhere as a
# string -- it has to be put back together from the template's body and the values that were substituted into
# it.
#
# The putting-back-together is upstream's own renderer, not a new one. `Whatsapp::TemplateContentRendererService`
# already does exactly this job for a conversation message (app/models/concerns/liquidable.rb:30-36), including
# the parts that are easy to get wrong: a media parameter renders as its fallback text rather than as a URL, and
# every substituted value is hidden behind a token before the Liquid pass so a customer's own `{{` cannot be
# re-rendered as a template.
#
# The values are passed through unchanged (`value_renderer` is identity) and the drops are empty, because the
# campaign path has already resolved this contact's Liquid before the send
# (app/services/whatsapp/liquid_template_processor_service.rb). Rendering them twice is how a value gets
# interpreted as a template.
#
# The template is looked up in the channel's own synced snapshot, which is the list the send path resolves
# against (app/services/whatsapp/template_processor_service.rb:29-35). If it is not there, or its body has no
# text, the result is nil -- and the recipient list renders "message not generated" rather than a guess
# (app/javascript/.../CampaignDeliveryTable.vue:47-49).
#
# This is a message body, which is exactly what an audit record may never carry (package B §5). It belongs on
# the recipient row and nowhere else.
class Campaigns::RenderedTemplateText
  IDENTITY = ->(value) { value }
  APPROVED = 'approved'.freeze

  def initialize(channel:, template_params:)
    @channel = channel
    @template_params = template_params.presence || {}
  end

  # nil rather than a half-rendered string if the template cannot be rendered: a wrong message in the recipient
  # list is worse than an honest "not generated", and a campaign must not fail over its own reporting.
  def text
    body = body_text
    return nil if body.blank?

    Whatsapp::TemplateContentRendererService.new(
      content: body, body_params: body_params, value_renderer: IDENTITY, message_drops: {}
    ).perform
  rescue StandardError => e
    Rails.logger.warn("[Lynomia::Campaigns] could not render the sent text for a recipient: #{e.class}")
    nil
  end

  private

  def body_text
    component('BODY')&.dig('text')
  end

  def component(type)
    Array(template['components']).find { |entry| entry['type'].to_s.upcase == type }
  end

  def template
    @template ||= Array(@channel.message_templates).find { |entry| requested?(entry) } || {}
  end

  # The same three conditions the send path resolves a template by: the name, the language case-insensitively,
  # and Meta having approved it.
  def requested?(entry)
    entry['name'] == @template_params['name'] &&
      entry['language'].to_s.downcase == @template_params['language'].to_s.downcase &&
      entry['status'].to_s.downcase == APPROVED
  end

  # The body's variable values, keyed the way the template's own placeholders are: by position for a POSITIONAL
  # template, by name for a NAMED one. The converter is what turns either of the two shapes a client may send
  # into that one hash, and is the same call the send path makes.
  def body_params
    Whatsapp::TemplateParameterConverterService
      .new(@template_params.deep_dup, template.presence)
      .normalize_to_enhanced
      .dig('processed_params', 'body') || {}
  end
end
