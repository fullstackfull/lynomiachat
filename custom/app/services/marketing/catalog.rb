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
#
# `related` and `channels` are the internal link graph. They are curated rather than computed because a
# useful "see also" is a product judgement -- WhatsApp's neighbours are the template manager and campaigns,
# not the other nine channels. Both are also the mechanism behind the rule that this site has no orphan page:
# every entry with a page of its own is reachable from its index and from at least one sibling.
module Marketing::Catalog
  # state: :available  -- no flag, no entitlement, no credential beyond the customer's own channel account
  #        :conditional -- reachable only when the named prerequisite is met; the prerequisite is rendered
  #        :beta        -- the product itself labels it beta
  Entry = Struct.new(:id, :state, :docs, :detail, :related, :channels, keyword_init: true) do
    def slug
      id.to_s.tr('_', '-')
    end

    # Every entry has a page of its own except where the inventory's verdict is "mention only", so `detail:
    # false` is written once rather than `detail: true` nineteen times.
    def detail?
      detail != false
    end

    def related_ids
      Array(related)
    end

    def channel_ids
      Array(channels)
    end
  end

  FEATURES = [
    Entry.new(id: :unified_inbox, state: :available, docs: 'connect-your-first-channel',
              related: %i[team_collaboration auto_assignment canned_responses]),
    Entry.new(id: :team_collaboration, state: :available, docs: 'roles-and-permissions',
              related: %i[unified_inbox auto_assignment security]),
    Entry.new(id: :auto_assignment, state: :available, docs: 'connect-your-first-channel',
              related: %i[team_collaboration unified_inbox analytics]),
    Entry.new(id: :contact_management, state: :available, docs: nil,
              related: %i[audiences unified_inbox commerce]),
    Entry.new(id: :canned_responses, state: :available, docs: nil,
              related: %i[unified_inbox automation whatsapp_templates]),
    Entry.new(id: :automation, state: :available, docs: 'campaigns-or-automation',
              related: %i[canned_responses flow_builder auto_assignment]),
    Entry.new(id: :campaigns, state: :available, docs: 'live-chat-campaigns',
              related: %i[whatsapp_campaigns audiences analytics], channels: %i[live_chat sms]),
    Entry.new(id: :whatsapp_campaigns, state: :conditional, docs: 'whatsapp-campaigns',
              related: %i[whatsapp_templates audiences analytics], channels: %i[whatsapp]),
    Entry.new(id: :audiences, state: :available, docs: 'shared-audiences',
              related: %i[contact_management campaigns whatsapp_campaigns]),
    Entry.new(id: :whatsapp_templates, state: :available, docs: nil,
              related: %i[whatsapp_campaigns flow_builder canned_responses], channels: %i[whatsapp]),
    Entry.new(id: :analytics, state: :available, docs: nil,
              related: %i[csat auto_assignment campaigns]),
    Entry.new(id: :csat, state: :available, docs: nil,
              related: %i[analytics unified_inbox support_desk]),
    Entry.new(id: :flow_builder, state: :conditional, docs: nil,
              related: %i[automation whatsapp_templates agent_bots], channels: %i[whatsapp]),
    Entry.new(id: :ai_assist, state: :conditional, docs: nil,
              related: %i[canned_responses translation agent_bots]),
    Entry.new(id: :agent_bots, state: :available, docs: nil,
              related: %i[api_webhooks flow_builder ai_assist]),
    Entry.new(id: :translation, state: :conditional, docs: nil,
              related: %i[ai_assist unified_inbox]),
    Entry.new(id: :commerce, state: :conditional, docs: 'commerce-overview',
              related: %i[contact_management unified_inbox analytics]),
    Entry.new(id: :api_webhooks, state: :available, docs: 'webhooks',
              related: %i[agent_bots automation], channels: %i[api_channel live_chat]),
    Entry.new(id: :support_desk, state: :available, docs: 'contact-lynomia-support',
              related: %i[csat security]),
    Entry.new(id: :security, state: :available, docs: 'audit-logs',
              related: %i[team_collaboration support_desk])
  ].freeze

  # Nine channels, which is the honest count. TikTok is beta and is listed as such. Twitter/X, voice and
  # 360dialog are deliberately absent: the inventory could not establish a usable connect path for any of them.
  CHANNELS = [
    Entry.new(id: :whatsapp, state: :available, docs: 'connect-whatsapp',
              related: %i[whatsapp_templates whatsapp_campaigns flow_builder]),
    Entry.new(id: :live_chat, state: :available, docs: 'connect-your-first-channel',
              related: %i[campaigns unified_inbox api_webhooks]),
    Entry.new(id: :email, state: :available, docs: nil,
              related: %i[unified_inbox canned_responses auto_assignment]),
    Entry.new(id: :sms, state: :available, docs: nil,
              related: %i[campaigns contact_management]),
    Entry.new(id: :telegram, state: :available, docs: nil,
              related: %i[unified_inbox automation]),
    Entry.new(id: :line, state: :available, docs: nil,
              related: %i[unified_inbox automation]),
    Entry.new(id: :facebook_messenger, state: :conditional, docs: nil,
              related: %i[unified_inbox auto_assignment]),
    Entry.new(id: :instagram, state: :conditional, docs: nil,
              related: %i[unified_inbox commerce]),
    Entry.new(id: :api_channel, state: :available, docs: nil,
              related: %i[api_webhooks agent_bots]),
    # The one entry with no page of its own: the inventory's verdict is "mention only, labelled beta", because
    # the tile appears only on an installation configured for TikTok (02-verified-feature-inventory.md §1).
    Entry.new(id: :tiktok, state: :beta, docs: nil, detail: false)
  ].freeze

  COLLECTIONS = { features: FEATURES, channels: CHANNELS }.freeze

  def self.features = FEATURES
  def self.channels = CHANNELS
  def self.channel_count = CHANNELS.count { |entry| entry.state != :beta }

  # `fetch`, not a lookup with a fallback: the only caller allowlists the scope before asking
  # (Marketing::EntriesController::SCOPES), so an unknown scope here is a programming error and should say so.
  def self.entries(scope) = COLLECTIONS.fetch(scope)

  def self.find(scope, slug)
    entries(scope).find { |entry| entry.detail? && entry.slug == slug }
  end

  def self.feature(id) = FEATURES.find { |entry| entry.id == id }
  def self.channel(id) = CHANNELS.find { |entry| entry.id == id }
end
