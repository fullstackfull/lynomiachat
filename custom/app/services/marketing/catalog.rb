# The verified catalogue the marketing site renders from.
#
# EVERY ENTRY TRACES TO docs/official-website/02-verified-feature-inventory.md, which was built by reading the
# code rather than the old marketing page. The `state` is the inventory's verdict and it is rendered on the
# page, not hidden: a feature that needs a flag, a credential or a plan entitlement says so where a reader can
# see it. That is the rule the previous site broke in six places.
#
# WHY A CONSTANT AND NOT A DATABASE TABLE, yet. These are product facts, not operator copy: the fact that Flow
# Builder needs a WhatsApp Cloud inbox is not something an operator should be able to edit away. W4 adds
# operator-editable copy around these entries (SitePage), and the entry itself stays here beside the evidence.
#
# `docs` is the slug under custom/db/documentation, resolved through the existing /docs/:article_slug route so
# the link survives a portal slug change (config/routes/documentation.rb:59-60).
module Marketing::Catalog
  # state: :available  -- no flag, no entitlement, no credential beyond the customer's own channel account
  #        :conditional -- reachable only when the named prerequisite is met; the prerequisite is rendered
  #        :beta        -- the product itself labels it beta
  Entry = Struct.new(:id, :state, :docs, keyword_init: true)

  FEATURES = [
    Entry.new(id: :unified_inbox, state: :available, docs: 'connect-your-first-channel'),
    Entry.new(id: :team_collaboration, state: :available, docs: 'roles-and-permissions'),
    Entry.new(id: :auto_assignment, state: :available, docs: 'connect-your-first-channel'),
    Entry.new(id: :contact_management, state: :available, docs: nil),
    Entry.new(id: :canned_responses, state: :available, docs: nil),
    Entry.new(id: :automation, state: :available, docs: 'campaigns-or-automation'),
    Entry.new(id: :campaigns, state: :available, docs: 'live-chat-campaigns'),
    Entry.new(id: :whatsapp_campaigns, state: :conditional, docs: 'whatsapp-campaigns'),
    Entry.new(id: :audiences, state: :available, docs: 'shared-audiences'),
    Entry.new(id: :whatsapp_templates, state: :available, docs: nil),
    Entry.new(id: :analytics, state: :available, docs: nil),
    Entry.new(id: :csat, state: :available, docs: nil),
    Entry.new(id: :flow_builder, state: :conditional, docs: nil),
    Entry.new(id: :ai_assist, state: :conditional, docs: nil),
    Entry.new(id: :commerce, state: :conditional, docs: 'commerce-overview'),
    Entry.new(id: :api_webhooks, state: :available, docs: 'webhooks'),
    Entry.new(id: :support_desk, state: :available, docs: 'contact-lynomia-support'),
    Entry.new(id: :security, state: :available, docs: 'audit-logs')
  ].freeze

  # Nine channels, which is the honest count. TikTok is beta and is listed as such. Twitter/X, voice and
  # 360dialog are deliberately absent: the inventory could not establish a usable connect path for any of them.
  CHANNELS = [
    Entry.new(id: :whatsapp, state: :available, docs: 'connect-whatsapp'),
    Entry.new(id: :live_chat, state: :available, docs: 'connect-your-first-channel'),
    Entry.new(id: :email, state: :available, docs: nil),
    Entry.new(id: :sms, state: :available, docs: nil),
    Entry.new(id: :telegram, state: :available, docs: nil),
    Entry.new(id: :line, state: :available, docs: nil),
    Entry.new(id: :facebook_messenger, state: :conditional, docs: nil),
    Entry.new(id: :instagram, state: :conditional, docs: nil),
    Entry.new(id: :api_channel, state: :available, docs: nil),
    Entry.new(id: :tiktok, state: :beta, docs: nil)
  ].freeze

  def self.features = FEATURES
  def self.channels = CHANNELS
  def self.channel_count = CHANNELS.count { |entry| entry.state != :beta }
end
