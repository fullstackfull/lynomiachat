# Be sure to restart your server when you modify this file.
# Sessions are used only for the super_admin dashboard (flash/CSRF), not for API auth.

# Secure by default in production: the session cookie carries the super admin's session, and a cookie without this
# flag is sent over plain HTTP. An installation genuinely served without TLS has to say so with FORCE_SSL=false.
secure_cookies = ActiveModel::Type::Boolean.new.cast(ENV.fetch('FORCE_SSL', Rails.env.production?))

Rails.application.config.session_store :cookie_store,
                                       key: '_chatwoot_session',
                                       same_site: :lax,
                                       secure: secure_cookies,
                                       httponly: true
