# frozen_string_literal: true

# Customizations injected into core classes (code lives in custom/app).
# Runs on boot and on every code reload in development.
#
# A LIST OF PAIRS, NOT A HASH. Inbox now takes two extensions, and a hash literal with the same
# key twice silently keeps only the last one -- which would have dropped Billing::InboxLimit and
# turned off plan inbox limits and channel entitlement without a single error.
Rails.application.config.to_prepare do
  [
    [Api::V1::Accounts::BaseController, Billing::AccessGuard],
    [Inbox, Billing::InboxLimit],
    [AccountUser, Billing::AgentLimit],
    # Channel exclusivity rides here for the same reason the limits do: inbox creation has nine
    # production call sites in this fork and Inbox validation is the only point downstream of all
    # of them. See Channels::ExclusivityGuard.
    [Inbox, Channels::ExclusivityGuard]
  ].each do |klass, extension|
    klass.include(extension) unless klass.include?(extension)
  end
end
