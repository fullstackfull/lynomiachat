# Zid Merchant API (https://api.zid.sa/v1) with the store's OAuth tokens from the Zid app authorization
# (docs/commerce/14-zid-oauth-and-tokens.md). Read-only: only GET requests exist here. The API host is fixed by Zid,
# never taken from a store or tenant setting.
class Commerce::Providers::Zid < Commerce::Providers::Base
  API_BASE = URI('https://api.zid.sa/v1').freeze

  def self.enabled? = Commerce::Zid::Config.enabled?
end
