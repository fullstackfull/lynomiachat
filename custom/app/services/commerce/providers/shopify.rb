# Shopify Admin GraphQL API with the store's expiring offline token from the Lynomia Commerce Shopify app
# (docs/commerce/19-shopify-graphql-provider.md). Read-only: queries only. The API host is the store's validated
# myshopify.com domain, never a URL from a response.
class Commerce::Providers::Shopify < Commerce::Providers::Base
  def self.enabled? = Commerce::Shopify::Config.enabled?
end
