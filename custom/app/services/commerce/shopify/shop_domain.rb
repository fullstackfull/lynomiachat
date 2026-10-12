# A Shopify store's own identity: its `*.myshopify.com` domain.
#
# This is the shop domain's one definition for the whole product. It was `Shopify::ShopDomain` under
# app/services/shopify/, the legacy integration's directory, while Lynomia Commerce reached across into that
# namespace for it (docs/product-refinement/02-shopify-retirement.md §4). Retiring the legacy integration
# deletes that directory, so the primitive moves here -- to the architecture that actually owns Shopify now --
# rather than being deleted with the surface around it or left behind as the one survivor of a removed module.
#
# `Integrations::Hook` still validates a legacy hook's `reference_id` against FORMAT. That is deliberate: the
# legacy ROWS are not destroyed by the retirement, so a row an operator has not migrated yet must stay valid,
# loadable and deletable (§5).
#
# A custom storefront domain is rejected on purpose. Shopify identifies a store by its myshopify domain, and a
# merchant may point several custom domains at one store -- so accepting one would let the same store be
# connected twice under two names, which the unique index on (provider, external_store_id) exists to prevent.
class Commerce::Shopify::ShopDomain
  FORMAT = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.myshopify\.(?:com|io)\z/

  # `.myshopify.io` is Shopify's development-store suffix, which is what a partner tests against.

  def self.normalize(value)
    value.to_s.strip.downcase
  end

  def self.valid?(value)
    normalize(value).match?(FORMAT)
  end
end
