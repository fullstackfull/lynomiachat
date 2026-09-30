# Explicit allow-list: credentials never leave the backend.
json.id store.id
json.provider store.provider
json.provider_enabled Commerce::Providers.enabled?(store.provider)
json.name store.name
json.base_url store.base_url
json.status store.status
json.verified_at store.metadata['verified_at']
json.created_at store.created_at.to_i
