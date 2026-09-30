# Provider registry. Adding a provider means a Commerce::Providers::Base subclass and one entry here.
module Commerce::Providers
  REGISTRY = { 'woocommerce' => 'Commerce::Providers::Woocommerce', 'salla' => 'Commerce::Providers::Salla' }.freeze

  def self.for(store, credentials: store.credentials)
    REGISTRY.fetch(store.provider).constantize.new(store, credentials: credentials)
  end

  # The installation's provider switch (Super Admin). The `lynomia_commerce` plan feature is a separate, account-level check.
  def self.enabled?(provider)
    REGISTRY.fetch(provider).constantize.enabled?
  end

  def self.enabled
    REGISTRY.keys.select { |provider| enabled?(provider) }
  end
end
