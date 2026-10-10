json.payload @stores, partial: 'api/v1/accounts/commerce/stores/store', as: :store
# The providers an administrator can connect on this installation (Super Admin provider switches).
json.providers Commerce::Providers.enabled
# The stores this account keeps connected (disconnected ones do not count) and how many it may. nil is
# unlimited. Counted and capped exactly as Commerce::StoreConnection's own gate does, so the number shown here
# is the number that will refuse the next connection.
json.store_limit do
  json.used Billing::ResourceLimit.current_count(Current.account, :stores)
  json.limit Billing::Entitlements.limit(Current.account, :stores)
end
