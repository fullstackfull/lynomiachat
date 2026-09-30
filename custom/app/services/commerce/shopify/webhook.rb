# Receiving the Lynomia Commerce Shopify app's webhooks (docs/commerce/20-shopify-webhooks-and-compliance.md). They are
# app-specific subscriptions declared once in the app's configuration (shopify.app.toml), not created per shop, and all
# are delivered to POST /webhooks/shopify_commerce. The legacy Shopify integration keeps /webhooks/shopify, its own
# subscriptions and its own secret.
#
# Order events only drop cached orders; app/uninstalled and Shopify's mandatory privacy topics remove what Lynomia keeps
# (Commerce::Shopify::WebhookJob).
module Commerce::Shopify::Webhook
  ORDER_TOPICS = %w[orders/create orders/updated].freeze
  COMPLIANCE_TOPICS = %w[customers/data_request customers/redact shop/redact].freeze
  TOPICS = (ORDER_TOPICS + COMPLIANCE_TOPICS + %w[app/uninstalled]).freeze

  # Shopify's signature: the base64 HMAC-SHA256 of the raw body, keyed with the app's client secret, compared in constant
  # time before the body is parsed.
  def self.authentic?(raw_body, signature)
    return false unless signature.is_a?(String) && signature.present?

    expected = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', Commerce::Shopify::Config.client_secret, raw_body))
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end
end
