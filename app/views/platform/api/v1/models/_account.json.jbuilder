json.id resource.id
json.name resource.name
json.locale resource.locale
json.domain resource.domain
json.support_email resource.support_email
json.features resource.enabled_features
json.custom_attributes resource.custom_attributes
json.limits resource.limits
json.status resource.status
# WHOSE WORKSPACE THIS IS, and the only way a partner can find out (blocker B5).
#
# `platform_owned` marks an account the INSTALLATION runs rather than one it sells. Lynomia's
# own UTILITY-only gate for platform sending keys on it
# (custom/app/services/custom/whatsapp/send_on_whatsapp_service.rb#platform_workspace?), and the
# account index deliberately rejects platform-owned accounts so a partner cannot stumble on one
# and adopt it for a store (Platform::Api::V1::AccountsController#index).
#
# That left a partner unable to CONFIRM the account it was told is the platform workspace really
# is one. Store Syria addresses it by a configured id an operator types; pointed at a merchant's
# account, it would send the installation's operational notices from that merchant's own WhatsApp
# channel -- and the UTILITY gate would not apply either, because the gate reads this flag.
#
# READ-ONLY, AND IT LEAKS NOTHING. `show` is permissible-checked, so an app only ever sees this
# for an account it already holds. The flag stays out of `permitted_params` -- an ownership flag
# a tenant's own integration can set on itself is not an ownership flag -- so exposing it here
# tells a partner what it is and never lets it decide.
json.platform_owned resource.platform_owned
