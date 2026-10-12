# What this installation knows about each channel, in one place (docs/p10/02-channel-capability-matrix.md).
#
# WHY THIS EXISTS. Before P10 the answer to "what kind of channel is this" was spread across five partial
# vocabularies that did not agree: twelve predicates on Inbox, `INBOX_TYPES` plus `CHANNEL_TYPES` plus
# `INBOX_IDENTIFIER_RESOLVERS` (eight of twelve channels) in the dashboard, about twenty branches in
# `_inbox.json.jbuilder`, and `Flows::ChannelCapabilities`, which knows only WhatsApp Cloud. Adding a channel
# meant finding all five.
#
# WHAT THIS IS NOT. It is not a sixth vocabulary that half-replaces the others. It holds exactly the three
# dimensions P10 needs and that nothing else owns -- how a contact is identified, what kind of connection the
# channel has, and where this fork learns that the connection is broken. Icons, flow node limits and the
# outbound service map stay where they are, because they answer different questions:
#
#   icons and labels                 app/javascript/dashboard/helper/inbox.js  -- rendering
#   flow node limits                 custom/app/services/flows/channel_capabilities.rb -- flow authoring
#   which service sends a reply      SendReplyJob::CHANNEL_SERVICES -- outbound routing
#
# Those three are not duplicated here and this does not try to absorb them; doing so would mean touching 297
# `Channel::` literals across 68 frontend files for no gain in correctness.
#
# EVERY ROW IS A REPOSITORY FACT, not an aspiration. `health_sources` in particular lists only what some code
# path in THIS fork actually writes or stores, which is why five channels have none: nothing in the repository
# reports whether a LINE, Telegram, Twilio, Bandwidth SMS or X connection still works. P10 says `unknown` for
# those rather than inventing a probe or guessing a provider's semantics.
module Channels::Capability
  # How the next message from this channel is matched to a contact (docs/p10/00-discovery.md §2).
  #   phone            the source_id IS the customer's phone number
  #   email            the source_id IS the customer's email address
  #   provider_scoped  an opaque id that means nothing outside this provider
  #   anonymous        a token this installation minted; identifies a session, not a person
  IDENTITIES = %i[phone email provider_scoped anonymous].freeze

  # What there is to stay connected to.
  #   none                 no external provider; the channel cannot be disconnected
  #   provider_credential  a key, token or secret this installation stores
  #   provider_oauth       an authorization a person granted, which can be revoked or expire
  CONNECTIONS = %i[none provider_credential provider_oauth].freeze

  # Where this fork learns the connection is broken.
  #   reauth_latch     the channel calls authorization_error! / prompt_reauthorization! (Reauthorizable)
  #   token_expiry     the channel row stores a real expiry timestamp
  #   provider_health  the provider's own health is fetched and stored
  HEALTH_SOURCES = %i[reauth_latch token_expiry provider_health].freeze

  Entry = Data.define(:key, :channel_type, :identity, :connection, :health_sources) do
    def provider_backed? = connection != :none
    def health_reported? = health_sources.any?
    def health_source?(source) = health_sources.include?(source)
  end

  # Twelve channels, which is every `Channel::` model in this fork. `key` reuses the dashboard's existing
  # `CHANNEL_TYPES` slug wherever one exists; `twilio` and `twitter` have no slug there and take the obvious one.
  ENTRIES = [
    # No provider. A web widget is served by this installation and an API inbox is driven by its own client, so
    # there is nothing to authenticate against and nothing that can go stale.
    [:website, 'Channel::WebWidget', :anonymous, :none, []],
    [:api, 'Channel::Api', :provider_scoped, :none, []],

    # Meta. All four latch through Reauthorizable; Instagram and TikTok additionally store a real token expiry,
    # and WhatsApp additionally stores the provider's own phone-number health.
    [:facebook, 'Channel::FacebookPage', :provider_scoped, :provider_oauth, [:reauth_latch]],
    [:instagram, 'Channel::Instagram', :provider_scoped, :provider_oauth, [:reauth_latch, :token_expiry]],
    [:tiktok, 'Channel::Tiktok', :provider_scoped, :provider_oauth, [:reauth_latch, :token_expiry]],
    [:whatsapp, 'Channel::Whatsapp', :phone, :provider_credential, [:reauth_latch, :provider_health]],

    # Email is both: IMAP/SMTP credentials this installation stores, or a Google or Microsoft authorization.
    # `Inboxes::FetchImapEmailsJob` latches either way.
    [:email, 'Channel::Email', :email, :provider_credential, [:reauth_latch]],

    # Credentials this installation stores, and nothing that reports whether they still work. Their send paths
    # surface a failure on the MESSAGE (status failed, external_error) but nothing is recorded against the
    # channel, so its connection state is `unknown` rather than green.
    [:telegram, 'Channel::Telegram', :provider_scoped, :provider_credential, []],
    [:line, 'Channel::Line', :provider_scoped, :provider_credential, []],
    [:twilio, 'Channel::TwilioSms', :phone, :provider_credential, []],
    [:sms, 'Channel::Sms', :phone, :provider_credential, []],
    [:twitter, 'Channel::TwitterProfile', :provider_scoped, :provider_credential, []]
  ].map { |key, channel_type, identity, connection, sources| Entry.new(key, channel_type, identity, connection, sources) }.freeze

  BY_CHANNEL_TYPE = ENTRIES.index_by(&:channel_type).freeze
  BY_KEY = ENTRIES.index_by(&:key).freeze

  module_function

  # @param channel_type [String] e.g. 'Channel::Whatsapp'
  # @return [Entry, nil] nil for a channel type this fork does not have, which a caller must treat as unknown
  #   rather than as a default -- a channel nobody has described is exactly the case that must not render green.
  def for_channel_type(channel_type) = BY_CHANNEL_TYPE[channel_type.to_s]

  def for_inbox(inbox) = for_channel_type(inbox.channel_type)

  def identity_of(inbox) = for_inbox(inbox)&.identity
end
