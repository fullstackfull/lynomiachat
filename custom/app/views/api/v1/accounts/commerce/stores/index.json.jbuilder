json.payload @stores, partial: 'api/v1/accounts/commerce/stores/store', as: :store
# The providers an administrator can connect on this installation (Super Admin provider switches).
json.providers Commerce::Providers.enabled
# The account's plan: the stores it keeps connected (disconnected ones do not count) and how many it may; nil is unlimited.
json.store_limit do
  json.used(@stores.to_a.count { |store| !store.disconnected? })
  json.limit Billing::PlanLimits.limit_for(Current.account, :stores)
end
