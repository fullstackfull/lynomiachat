# Explicit allow-list: credentials never leave the backend.
json.id store.id
json.provider store.provider
json.provider_enabled Commerce::Providers.enabled?(store.provider)
json.name store.name
json.base_url store.base_url
json.status store.status
json.verified_at store.metadata['verified_at']
# Live updates: active, read_only_key (the key cannot create webhooks), or nil (not set up for this store).
json.realtime_status store.metadata.dig('realtime', 'status')
# Order actions: the administrator's opt-in, and whether they can work: available, or why not (unsupported,
# actions_disabled, provider_actions_disabled, read_only_key, missing_scope).
json.order_actions store.settings['order_actions'] == true
json.order_actions_status Commerce::OrderActions.store_status(store)
json.created_at store.created_at.to_i
