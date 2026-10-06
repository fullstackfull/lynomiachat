# frozen_string_literal: true

# How a Lynomia WhatsApp diagnosis reads installation configuration — the one place that decides it, for the same
# reason Report is the one place that decides masking.
#
# The ordinary accessors cannot be used here, because both of them WRITE:
#
#   GlobalConfigService.load(key, default)
#     ends in `InstallationConfig.where(name: key).first_or_create(value: config_value, locked: false)` followed by
#     `GlobalConfig.clear_cache` (lib/global_config_service.rb:12-14). So reading a key that has no row, with a
#     non-blank ENV value or default, CREATES the row and then expires every cached global-config key in Redis.
#
#   GlobalConfig.get_value(key)
#     ends in `conn.set(cache_key, …, ex: 1.day)` whenever the cache is cold (lib/global_config.rb:46-50), so it
#     writes to Redis too.
#
# This was not theoretical. The diagnosis task left exactly one row behind — `WHATSAPP_API_VERSION`, whose default
# `v24.0` is non-blank — and on a production server the same path would have written `WHATSAPP_APP_SECRET` into the
# database if it were set in ENV but had no row. A diagnosis that mutates the thing it is diagnosing is worthless,
# and one that writes a credential is worse than worthless.
#
# So the read is the plain SELECT that `GlobalConfig#db_fallback` itself uses, then ENV, then the caller's default.
# What it reports is therefore the STORED value. If Redis holds a stale cached value, the application is acting on
# the cache while this reports the database — which is the right bias for a diagnosis, since the database is the
# source of truth and the cache expires within a day.
module Whatsapp::Diagnosis::StoredConfig
  def stored_config(key, default = nil)
    row = InstallationConfig.find_by(name: key)
    return row.value if row && row.value.present?

    ENV.fetch(key, default)
  end
end
