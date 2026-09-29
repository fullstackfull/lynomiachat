# frozen_string_literal: true

# Billing customization (code lives in custom/app)
# Runs on boot and on every code reload in development.
Rails.application.config.to_prepare do
  {
    Api::V1::Accounts::BaseController => Billing::AccessGuard,
    Inbox => Billing::InboxLimit,
    AccountUser => Billing::AgentLimit
  }.each do |klass, extension|
    klass.include(extension) unless klass.include?(extension)
  end
end
