# Webhook (docs/flow-builder/04-node-contracts.md §webhook): posts the flow's state to a URL through Chatwoot's own webhook
# delivery (WebhookJob → Webhooks::Trigger → SafeFetch: private addresses refused, timeouts), signed with the flow bot's
# secret (X-Chatwoot-Signature: sha256 HMAC of "<timestamp>.<body>", as Chatwoot's bot webhooks are). Delivered in the
# background and never waited for: the response is not read and nothing it returns enters the flow, so the flow follows
# `next` at once. Accounts whose plan has no API and webhooks deliver nothing.
#
# Payload: event `flow_webhook`, the flow (bot id and name, version, node, session), Chatwoot's conversation webhook data
# (with its contact), and the run's values: the last reply, values the flow stored, the order a lookup found.
class Flows::Nodes::Webhook < Flows::Nodes::Base
  def enter
    if Flows::Simulator.active?
      Flows::Log.event('flow.webhook.simulated', @run.session, node_id: @node['id'])
    elsif account.api_and_webhooks_enabled?
      WebhookJob.perform_later(@data['url'], payload, :flow_webhook, secret: @run.bot.secret, delivery_id: SecureRandom.uuid)
    else
      Flows::Log.event('flow.webhook.skipped', @run.session, node_id: @node['id'], reason: 'plan')
    end
    Flows::Step.next('next')
  end

  private

  def payload
    {
      event: 'flow_webhook',
      flow: { id: @run.bot.id, name: @run.bot.name, version: @run.version.version, node_id: @node['id'], session_id: @run.session.id },
      conversation: conversation.webhook_data,
      reply: @run.context['reply'], values: @run.context['values'] || {}, order: @run.context['order']
    }
  end
end
