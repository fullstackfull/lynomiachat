# What a flow may send on an inbox's channel (docs/flow-builder/06-whatsapp-channel-capabilities.md). The backend
# decides; the builder shows what this answers. Phase 1 runs flows on WhatsApp Cloud inboxes (the WhatsApp API and
# WhatsApp Business coexistence numbers alike); other channels are not offered yet.
#
# WhatsApp limits are Meta's documented ones for interactive messages, applied before anything is sent because
# Chatwoot's provider sends whatever it is given: reply buttons at most 3, title 20 characters; list one section (as
# Chatwoot sends it) of at most 10 rows, title 24, description 72, button 20; interactive body 1024; text 4096.
module Flows::ChannelCapabilities
  WHATSAPP = {
    text: { body: 4096 },
    buttons: { max: 3, title: 20, body: 1024 },
    list: { max: 10, title: 24, description: 72, body: 1024, button: 20 },
    template: true,
    reply_window: 24.hours
  }.freeze

  NODE_NEEDS = { 'buttons' => :buttons, 'list' => :list }.freeze

  def self.for(inbox)
    channel = inbox.channel
    WHATSAPP if channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  # The node types an inbox cannot run, from the given ones.
  def self.unsupported(inbox, node_types)
    capabilities = self.for(inbox)
    return node_types.uniq if capabilities.nil?

    node_types.uniq.select { |type| NODE_NEEDS.key?(type) && !capabilities.key?(NODE_NEEDS[type]) }
  end
end
