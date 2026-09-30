# Zid's OAuth 2.0 Authorization Code grant, server-side only (docs/commerce/14-zid-oauth-and-tokens.md). Hosts are fixed
# by Zid, never taken from a store or tenant setting; the client secret only ever travels in the token requests below.
module Commerce::Zid::Oauth
  OAUTH_URI = URI('https://oauth.zid.sa').freeze
  API_URI = URI('https://api.zid.sa/v1').freeze

  # Where the administrator's browser is sent to authorize the Lynomia app. `state` is Commerce::OauthState's.
  def self.authorize_url(state)
    query = { client_id: Commerce::Zid::Config.client_id, redirect_uri: Commerce::Zid::Config.redirect_uri, response_type: 'code',
              state: state }
    "#{OAUTH_URI}/oauth/authorize?#{URI.encode_www_form(query)}"
  end

  # One token request, the authorization_code or the refresh_token grant: [HTTP status, parsed body]. Sent once and never
  # retried (Commerce::HttpClient#post_form).
  def self.token(grant)
    client = { client_id: Commerce::Zid::Config.client_id, client_secret: Commerce::Zid::Config.client_secret,
               redirect_uri: Commerce::Zid::Config.redirect_uri }
    Commerce::HttpClient.new(base_uri: OAUTH_URI, log_tag: 'zid').post_form('/oauth/token', grant.merge(client))
  end

  # The store the tokens belong to, from the manager profile: { external_store_id:, name:, base_url:, time_zone: }.
  # `user.store.id` is Zid's stable store id; the manager can be any of the store's staff, so the manager never identifies
  # the store. The store's time zone is how its order times are read (Zid sends them without a zone).
  def self.profile(credentials)
    store = api(credentials).get_json('/managers/account/profile').dig('user', 'store')
    id, name, url = store.values_at('id', 'title', 'url')
    raise TypeError, 'unexpected store' unless id.is_a?(Integer) && id.positive? && [name, url].all?(String)

    { external_store_id: id.to_s, name: name, base_url: url, time_zone: store['timezone'].presence }
  rescue TypeError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'zid_profile')
  end

  # A Merchant API client for one store: `Authorization: Bearer <authorization>` and `X-Manager-Token: <access_token>`.
  def self.api(credentials)
    Commerce::HttpClient.new(base_uri: API_URI, log_tag: 'zid', authorization: "Bearer #{credentials.fetch('authorization')}",
                             headers: { 'X-Manager-Token' => credentials.fetch('access_token') })
  end
end
