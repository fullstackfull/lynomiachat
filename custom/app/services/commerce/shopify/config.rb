# Installation-wide settings of the Lynomia Commerce Shopify app (Super Admin → Settings → Shopify Commerce). This is a
# dedicated Shopify app, separate from the legacy Shopify integration and its SHOPIFY_* settings: the two never share a
# client, callback, webhook endpoint or token (docs/commerce/21-shopify-legacy-coexistence.md). Merchant tokens never
# live here: they are each store's encrypted credentials (docs/commerce/18-shopify-oauth-and-tokens.md).
#
# `enabled?` is the installation's provider switch. It is separate from the `lynomia_commerce` plan feature, which
# decides which accounts have Commerce at all; both are required to connect or read a Shopify store.
module Commerce::Shopify::Config
  CALLBACK_PATH = '/commerce/shopify/callback'.freeze
  # The Admin GraphQL API version every request uses. Pinned, never `latest` or `unstable`: moving it is a reviewed change
  # (docs/commerce/19-shopify-graphql-provider.md).
  API_VERSION = '2026-07'.freeze
  # Read-only. The 2026-07 schema grants every field the connector reads (customers, orders, fulfillments and their
  # tracking) to these two scopes, so read_fulfillments and read_all_orders are not requested.
  SCOPES = %w[read_customers read_orders].freeze

  # Read from the config cache directly, like Commerce::Zid::Config.enabled?: it is checked on every Commerce request.
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(GlobalConfig.get_value('SHOPIFY_COMMERCE_ENABLED')) == true
  end

  def self.client_id = required('SHOPIFY_COMMERCE_CLIENT_ID')

  def self.client_secret = required('SHOPIFY_COMMERCE_CLIENT_SECRET')

  # The redirect URL allowed for the app in its Shopify configuration. It follows the installation's own URL instead of
  # a separate setting.
  def self.redirect_uri = "#{ENV.fetch('FRONTEND_URL')}#{CALLBACK_PATH}"

  # A value the running flow needs: missing means the app was set up incompletely, so it fails loudly.
  def self.required(name)
    GlobalConfigService.load(name, nil).presence || raise(KeyError, "#{name} is not configured")
  end
  private_class_method :required
end
