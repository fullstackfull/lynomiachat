# Send WhatsApp template (docs/flow-builder/04-node-contracts.md §send template): one of the inbox's templates, sent by
# Chatwoot's own template path: a bot message carrying `template_params` as the dashboard composer sends them, which
# Whatsapp::SendOnWhatsappService hands to Whatsapp::TemplateProcessorService and the provider's `send_template`, on WhatsApp
# API and coexistence numbers alike. Meta accepts approved templates after the 24-hour window, so unlike Send Message the
# node does not stop at a closed window.
#
# The node's values get the run's `flow.*` filled in (Flows::Variables); Chatwoot's own variables are rendered by the
# message (Liquidable). A template the inbox cannot send now (deleted, no longer approved, not in that language, not one
# the composer would send, a channel without templates) or a value left empty follows `failed`, or fails the session when
# `failed` is not connected: nothing else is sent in its place.
class Flows::Nodes::SendTemplate < Flows::Nodes::Base
  def enter
    template, problem = sendable_template
    return refuse(problem) if problem

    params = processed_params(template)
    return refuse('template_param_missing') if params.nil?

    @run.say(Flows::Template.body_text(template), additional_attributes: { 'template_params' => Flows::Template.template_params(template, params) })
    Flows::Step.next('next')
  end

  private

  def sendable_template
    inbox = conversation.inbox
    return [nil, 'template_unsupported'] unless Flows::ChannelCapabilities.for(inbox)&.dig(:template)

    problem = Flows::Template.problem(inbox, @data['name'], @data['language'])
    [problem ? nil : Flows::Template.find(inbox, @data['name'], @data['language']), problem]
  end

  def refuse(code)
    Flows::Log.event('flow.template.refused', @run.session, node_id: @node['id'], code: code)
    failed_connected? ? Flows::Step.next('failed') : Flows::Step.finish(:failed, code: code)
  end

  def failed_connected? = @run.version.edges.any? { |edge| edge['source'] == @node['id'] && edge['sourceHandle'] == 'failed' }

  # Chatwoot's processed_params for the template, or nil when a value it needs is empty once the run's values are in.
  def processed_params(template)
    params = Flows::Template.slots(template).each_with_object({}) do |(section, key, kind), result|
      value = Flows::Variables.render(Flows::Template.value(@data['params'], section, key), @run.context).strip
      next if value.empty? && kind == :media_name
      return nil if unusable?(value, kind)

      put(result, section, key, kind, value)
    end
    media_type = Flows::Template.media_type(template)
    params['header']['media_type'] = media_type if media_type
    params
  end

  def unusable?(value, kind) = value.empty? || (kind == :copy_code && value.length > Flows::Template::COPY_CODE_MAX)

  def put(params, section, key, kind, value)
    if section == 'buttons'
      (params['buttons'] ||= [])[key] = { 'type' => kind == :copy_code ? 'copy_code' : 'url', 'parameter' => value }
    else
      (params[section] ||= {})[key] = value
    end
  end
end
