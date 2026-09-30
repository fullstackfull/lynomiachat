# Shopify's OAuth authorization code grant for the Lynomia Commerce app, server-side only
# (docs/commerce/18-shopify-oauth-and-tokens.md). Every request goes to the shop's own myshopify.com host, always a
# Shopify::ShopDomain-validated value: the domain the administrator entered, carried in the signed state. The client
# secret only travels in the token requests below and is the key of the callback signature.
module Commerce::Shopify::Oauth
  # Shopify's official libraries accept a callback signed at most this many seconds before or after now.
  HMAC_TOLERANCE = 90
  SHOP_GID = %r{\Agid://shopify/Shop/(\d+)\z}
  SHOP_QUERY = 'query LynomiaShop { shop { id name myshopifyDomain } }'.freeze

  # Where the administrator's browser is sent to authorize the app. Without grant_options[]=per-user the token is an
  # offline token, the only kind background reads can use. `state` is Commerce::OauthState's.
  def self.authorize_url(shop, state)
    config = Commerce::Shopify::Config
    query = { client_id: config.client_id, scope: config::SCOPES.join(','), redirect_uri: config.redirect_uri, state: state }
    "https://#{shop}/admin/oauth/authorize?#{URI.encode_www_form(query)}"
  end

  # Shopify's HMAC over a callback query, computed as its official libraries do: every parameter except `hmac` and
  # `signature`, sorted by name, form-encoded with spaces as %20, HMAC-SHA256 with the client secret, hex; compared in
  # constant time. The signature's timestamp must be within HMAC_TOLERANCE.
  def self.valid_callback?(query, now: Time.current)
    signed = query.except('hmac', 'signature')
    return false unless query['hmac'].is_a?(String) && signed.values.all?(String) && recent?(signed['timestamp'], now)

    message = URI.encode_www_form(signed.sort).gsub('+', '%20')
    ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest('SHA256', Commerce::Shopify::Config.client_secret, message), query['hmac'])
  end

  # One token request, the authorization_code grant (with expiring=1) or the refresh_token grant: [HTTP status, parsed
  # body]. Sent once and never retried by the client (Commerce::HttpClient#post_json_status).
  def self.token(shop, grant)
    body = grant.merge(client_id: Commerce::Shopify::Config.client_id, client_secret: Commerce::Shopify::Config.client_secret)
    Commerce::HttpClient.new(base_uri: URI("https://#{shop}"), log_tag: 'shopify').post_json_status('/admin/oauth/access_token', body)
  end

  # The shop the token belongs to: { external_store_id:, name: }. The numeric id of the shop's GID is Shopify's stable
  # shop id; the domain Shopify reports must be the shop the token was requested for.
  def self.identity(shop, access_token)
    data = Commerce::Shopify::Graphql.new(shop, access_token).query(SHOP_QUERY)['shop']
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'shopify_shop') unless data.is_a?(Hash)

    id = data['id'].to_s[SHOP_GID, 1]
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'shopify_shop') unless id && data['name'].is_a?(String) && data['name'].present?
    raise Commerce::Error.new('AUTH_INVALID', reason: 'shopify_shop_mismatch') unless data['myshopifyDomain'] == shop

    { external_store_id: id, name: data['name'] }
  end

  def self.recent?(timestamp, now)
    seconds = Integer(timestamp.to_s, 10, exception: false)
    seconds.present? && (now.to_i - seconds).abs <= HMAC_TOLERANCE
  end
  private_class_method :recent?
end
