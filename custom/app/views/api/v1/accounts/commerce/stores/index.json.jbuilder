json.payload @stores, partial: 'api/v1/accounts/commerce/stores/store', as: :store
# The providers an administrator can connect on this installation (Super Admin provider switches).
json.providers Commerce::Providers.enabled
