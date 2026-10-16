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

  # Third-party services a customer connects, other than the channel providers.
  #
  # THE CHANNEL PROVIDERS ARE DELIBERATELY ABSENT. Twilio, Bandwidth, Meta, LINE and Telegram are how a
  # channel is connected and they are described on the channel's own page; repeating them here would be two
  # pages competing for the same search with the same sentences.
  #
  # WEBHOOKS AND DASHBOARD APPS ARE ABSENT for the same reason: they are the api_webhooks feature, and the
  # index links there rather than restating it.
  #
  # The upstream Shopify integration is not listed either. It was retired in favour of the Lynomia Commerce
  # Shopify connection (docs/pr/ PR.A), and `shopify_integration` is off; the Shopify entry below is the
  # commerce one.
  #
  # NOTION IS NOT LISTED, and the reason is the inventory's standard of proof rather than its feature flag.
  # A Notion workspace can be connected and disconnected (app/controllers/api/v1/accounts/integrations/
  # notion_controller.rb has exactly a `destroy`, and NotionConcern has exactly an OAuth client) and nothing
  # in the product then reads that hook. A connection with no consumer is an incomplete flow, so it is not a
  # feature this site may advertise -- a gate stated on the card would not make it one.
  INTEGRATIONS = [
    Entry.new(id: :woocommerce, state: :conditional, docs: 'commerce-overview', related: %i[commerce contact_management]),
    Entry.new(id: :salla, state: :conditional, docs: 'commerce-overview', related: %i[commerce contact_management]),
    Entry.new(id: :zid, state: :conditional, docs: 'commerce-overview', related: %i[commerce contact_management]),
    Entry.new(id: :shopify, state: :conditional, docs: 'commerce-overview', related: %i[commerce contact_management]),
    Entry.new(id: :slack, state: :available, docs: nil, related: %i[team_collaboration unified_inbox]),
    # Connections with no page of their own: each is a credential field and a switch, so a page for it would
    # be a heading over one sentence. They keep their card, their state and their prerequisite on the index.
    Entry.new(id: :openai, state: :available, docs: nil, detail: false),
    Entry.new(id: :google_translate, state: :available, docs: nil, detail: false),
    Entry.new(id: :dialogflow, state: :available, docs: nil, detail: false),
    Entry.new(id: :video_calls, state: :available, docs: nil, detail: false),
    Entry.new(id: :linear, state: :conditional, docs: nil, detail: false),
    Entry.new(id: :leadsquared, state: :conditional, docs: nil, detail: false)
  ].freeze

  # Who the product is for, expressed as compositions of the entries above rather than as claims of its own.
  #
  # A solution page says nothing new about the product: it says which verified capabilities serve a particular
  # job and what has to be set up for them. That constraint is deliberate -- it is how a page for an audience
  # avoids becoming the one place on the site where an unverified promise appears.
  SOLUTIONS = [
    Entry.new(id: :ecommerce, state: :available, docs: 'commerce-overview',
              related: %i[commerce whatsapp_campaigns contact_management automation],
              channels: %i[whatsapp live_chat instagram]),
    Entry.new(id: :customer_support, state: :available, docs: 'connect-your-first-channel',
              related: %i[unified_inbox auto_assignment csat analytics],
              channels: %i[email live_chat whatsapp]),
    Entry.new(id: :whatsapp_first, state: :available, docs: 'connect-whatsapp',
              related: %i[whatsapp_templates whatsapp_campaigns flow_builder analytics],
              channels: %i[whatsapp]),
    Entry.new(id: :sales_enquiries, state: :available, docs: 'shared-audiences',
              related: %i[audiences campaigns contact_management auto_assignment],
              channels: %i[live_chat whatsapp sms])
  ].freeze

  COLLECTIONS = {
    features: FEATURES, channels: CHANNELS, integrations: INTEGRATIONS, solutions: SOLUTIONS
  }.freeze

  def self.features = FEATURES
  def self.channels = CHANNELS
  def self.integrations = INTEGRATIONS
  def self.solutions = SOLUTIONS
  def self.channel_count = CHANNELS.count { |entry| entry.state != :beta }

  # `fetch`, not a lookup with a fallback: the only caller allowlists the scope before asking
  # (Marketing::EntriesController::SCOPES), so an unknown scope here is a programming error and should say so.
  def self.entries(scope) = COLLECTIONS.fetch(scope)

  def self.find(scope, slug)
    entries(scope).find { |entry| entry.detail? && entry.slug == slug }
  end

  def self.feature(id) = FEATURES.find { |entry| entry.id == id }
  def self.channel(id) = CHANNELS.find { |entry| entry.id == id }

  # THE BILLING SIDE'S NAME FOR A CHANNEL, TRANSLATED INTO THIS CATALOGUE'S.
  #
  # `billing_plans.channel_entitlements` holds Rails class names -- `Channel::Whatsapp`, `Channel::WebWidget`
  # -- validated against Channels::Capability::BY_CHANNEL_TYPE, which knows twelve of them. This catalogue
  # knows the TEN the website sells, under its own ids. The two lists are deliberately different sizes:
  # `Channel::TwilioSms` is the SMS entry's second provider rather than a second channel, and
  # `Channel::TwitterProfile` is a model with no connect path, which the verified inventory refuses to list
  # as a product at all.
  #
  # A type with no entry here returns nil, and the pricing page renders nothing for it rather than inventing
  # a name: a plan that sells a channel this site does not describe is a fact for the operator to resolve,
  # not for a public page to paper over.
  CHANNEL_TYPES = {
    'Channel::Whatsapp' => :whatsapp,
    'Channel::WebWidget' => :live_chat,
    'Channel::Email' => :email,
    'Channel::Sms' => :sms,
    'Channel::TwilioSms' => :sms,
    'Channel::Telegram' => :telegram,
    'Channel::Line' => :line,
    'Channel::FacebookPage' => :facebook_messenger,
    'Channel::Instagram' => :instagram,
    'Channel::Api' => :api_channel,
    'Channel::Tiktok' => :tiktok
  }.freeze

  def self.channel_for_type(channel_type)
    id = CHANNEL_TYPES[channel_type.to_s]
    channel(id) if id
  end
end
