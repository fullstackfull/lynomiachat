# frozen_string_literal: true

# Billing settings over the Platform API -- everything EXCEPT the installation's Stripe credentials.
#
# A Platform App token is an installation-level credential by upstream design: PlatformController exempts
# `create` from its permissible check (app/controllers/platform_controller.rb:7) and
# Platform::Api::V1::AccountsController#create makes new accounts installation-wide. But a credential that can
# REPLACE the installation's Stripe keys is a different thing from one that can administer accounts: a new
# `stripe_secret_key` points this installation's customers at another Stripe account, and a new
# `stripe_webhook_secret` both breaks every genuine delivery and re-opens the forged-event path that
# docs/p11/00-p10-security-closure.md SEC-7 closed. No integration needs either -- `stripe_configured` already
# says whether billing works -- so they are set in Super Admin only (docs/p11/07-security-performance.md §4).
class Platform::Api::V1::Billing::SettingsController < Platform::Api::V1::Billing::BaseController
  # GET /platform/api/v1/billing/settings
  def show
    render_data(settings_payload)
  end

  # PATCH /platform/api/v1/billing/settings
  def update
    ::Billing::Settings.update!(params.require(:settings).permit(*writable_keys))
    render_data(settings_payload)
  end

  private

  def writable_keys
    ::Billing::Settings::KEYS.reject { |_key, definition| definition[:type] == :secret }.keys
  end

  # `stripe_configured` stays: an integration has to be able to tell whether billing is set up. The keys
  # themselves, and even their masked hints, do not appear.
  def settings_payload
    ::Billing::ApiSerializer.settings.except(*secret_keys)
  end

  def secret_keys
    ::Billing::Settings::KEYS.select { |_key, definition| definition[:type] == :secret }.keys
  end
end
