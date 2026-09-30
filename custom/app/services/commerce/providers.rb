# Provider registry. Adding a provider means a Commerce::Providers::Base subclass and one entry here.
module Commerce::Providers
  REGISTRY = { 'woocommerce' => 'Commerce::Providers::Woocommerce' }.freeze

  def self.for(store, credentials: store.credentials)
    REGISTRY.fetch(store.provider).constantize.new(store, credentials: credentials)
  end
end
