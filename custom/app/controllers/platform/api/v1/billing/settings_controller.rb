# frozen_string_literal: true

class Platform::Api::V1::Billing::SettingsController < Platform::Api::V1::Billing::BaseController
  # GET /platform/api/v1/billing/settings
  def show
    render_data(::Billing::ApiSerializer.settings)
  end

  # PATCH /platform/api/v1/billing/settings
  # Secret keys: send a value to change them, omit (or send empty) to keep them.
  def update
    ::Billing::Settings.update!(params.require(:settings).permit(*::Billing::Settings::KEYS.keys))
    render_data(::Billing::ApiSerializer.settings)
  end
end
