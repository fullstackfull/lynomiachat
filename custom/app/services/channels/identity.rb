# What counts as "the same channel" for two different connections.
#
# WITHOUT NORMALIZATION AN EXCLUSIVITY RULE IS A FORMATTING RULE. +44 20 7946 0958, 442079460958
# and 00 44 20 7946 0958 are one telephone number and three different strings; Sales@Example.COM
# and sales@example.com are one mailbox. A unique index over whatever the caller typed would let
# the same number be claimed by two stores as long as they typed it differently, which is the
# failure the rule exists to prevent rather than a cosmetic problem.
#
# EACH PROVIDER IS ASKED ITS OWN QUESTION, because the identity is not the same KIND of thing
# across channels. A phone number is a number. A Facebook page is an opaque numeric id the
# provider issued. An email is a mailbox. Treating them uniformly would mean either over- or
# under-normalizing most of them.
#
# A PROVIDER WITH NO OPERATOR-SUPPLIED IDENTITY RETURNS NIL, and nil means "not claimable". A web
# widget is served by this installation and an API inbox is driven by its own client: their
# identifiers are minted here (has_secure_token), so they are unique by construction and there is
# nothing a second store could collide with. Claiming them would be theatre.
module Channels::Identity
  module_function

  # @return [Array(String, String), nil] [provider_key, normalized_identity], or nil when this
  #   channel has no operator-supplied identity worth claiming.
  def for_channel(channel)
    entry = Channels::Capability.for_channel_type(channel.class.name)
    return nil if entry.nil?

    raw = raw_identity(entry.key, channel)
    return nil if raw.blank?

    normalized = normalize(entry.key, raw)
    return nil if normalized.blank?

    [entry.key.to_s, normalized]
  end

  # The attribute each provider treats as the thing being connected, in preference order.
  #
  # A table rather than a case, because this is data: adding a provider is a line here, and the
  # whole mapping can be read at once. :website and :api are absent on purpose -- they mint their
  # own identifiers, so there is nothing an operator supplied and nothing to collide with.
  # Twilio lists two because a Twilio channel is a number OR a messaging service, never both (its
  # own validations enforce that), so the identity is whichever one it has.
  IDENTITY_ATTRIBUTES = {
    whatsapp: [:phone_number],
    sms: [:phone_number],
    twilio: [:phone_number, :messaging_service_sid],
    email: [:email],
    facebook: [:page_id],
    instagram: [:instagram_id],
    telegram: [:bot_token],
    line: [:line_channel_id],
    tiktok: [:business_id],
    twitter: [:profile_id]
  }.freeze

  def raw_identity(key, channel)
    IDENTITY_ATTRIBUTES.fetch(key, []).lazy.filter_map { |attribute| channel.try(attribute).presence }.first
  end

  def normalize(key, raw)
    value = raw.to_s.strip

    case key
    when :whatsapp, :sms, :twilio then normalize_phone(value)
    when :email then value.downcase
      # Provider-issued ids are opaque: compared exactly, never reshaped. Lowercasing a
      # case-sensitive token would merge two different channels.
    else value
    end
  end

  # E.164-ish: digits only, with a leading + restored. 00 is the other international prefix in
  # common use and collapses to the same number, so it is folded. No country is assumed for a
  # bare national number -- guessing one would silently equate two numbers in different countries.
  def normalize_phone(value)
    digits = value.gsub(/[^\d+]/, '')
    digits = digits.sub(/\A00/, '+') unless digits.start_with?('+')
    digits = "+#{digits}" unless digits.start_with?('+')

    digits
  end
end
