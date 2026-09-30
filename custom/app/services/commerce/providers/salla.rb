# Salla Merchant API (https://api.salla.dev/admin/v2) with the store's OAuth tokens from the Salla app installation
# (docs/commerce/11-salla-auth-and-token-lifecycle.md). Read-only: only GET requests exist here. The API host is fixed
# by Salla, never taken from a store or tenant setting.
class Commerce::Providers::Salla < Commerce::Providers::Base
  API_BASE = 'https://api.salla.dev/admin/v2'.freeze

  def self.enabled? = Commerce::Salla::Config.enabled?
end
