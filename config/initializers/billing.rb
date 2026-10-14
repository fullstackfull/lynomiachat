# frozen_string_literal: true

# Customizations injected into core classes (code lives in custom/app).
# Runs on boot and on every code reload in development.
#
# A LIST OF PAIRS, NOT A HASH. Inbox now takes two extensions, and a hash literal with the same
# key twice silently keeps only the last one -- which would have dropped Billing::InboxLimit and
# turned off plan inbox limits and channel entitlement without a single error.
Rails.application.config.to_prepare do
  pairs = [
    [Api::V1::Accounts::BaseController, Billing::AccessGuard],
    [Inbox, Billing::InboxLimit],
    [AccountUser, Billing::AgentLimit],
    # Channel exclusivity rides here for the same reason the limits do: inbox creation has nine
    # production call sites in this fork and Inbox validation is the only point downstream of all
    # of them. See Channels::ExclusivityGuard.
    [Inbox, Channels::ExclusivityGuard]
  ]

  # The other half of the same rule, on the channel row, because a channel's identity is editable
  # after creation and an inbox validation does not run when only the channel is saved.
  #
  # ONLY THE CHANNELS THAT HAVE AN OPERATOR-SUPPLIED IDENTITY. Channels::Identity is the one place
  # that says which those are; website and api mint their own identifiers and are absent from it,
  # so they are not injected and cannot be claimed. Deriving the list here rather than writing it
  # out keeps one answer to "which channels does exclusivity apply to".
  Channels::Identity::IDENTITY_ATTRIBUTES.each_key do |key|
    channel_class = Channels::Capability::BY_KEY.fetch(key).channel_type.constantize
    pairs << [channel_class, Channels::IdentityGuard]
  end

  pairs.each do |klass, extension|
    klass.include(extension) unless klass.include?(extension)
  end
end
