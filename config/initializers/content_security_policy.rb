# Be sure to restart your server when you modify this file.

# Stage one of a content security policy: only the directives that cannot break what the product legitimately loads.
#
#   object-src 'none'  no <object>/<embed>/<applet> anywhere in this product, so this closes a plugin-injection
#                      vector with nothing to regress.
#   base-uri 'self'    a <base> tag injected into a page can repoint every relative URL on it, including the API
#                      calls the dashboard makes. Nothing here sets <base>.
#
# No default-src, script-src or style-src yet, deliberately. Those have to be enumerated from what the dashboard, the
# widget, the SDK and the portal actually load (own assets, ASSET_CDN_HOST, Stripe, the Facebook SDK, fonts), and a
# policy that misses one source breaks a feature in production. frame-ancestors is deliberately absent too: the
# widget is meant to be framed by customer sites. Stage two adds those, report-only first.
Rails.application.config.content_security_policy do |policy|
  policy.object_src :none
  policy.base_uri :self
end

# For further information see the following documentation
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy

# Rails.application.config.content_security_policy do |policy|
#   policy.default_src :self, :https
#   policy.font_src    :self, :https, :data
#   policy.img_src     :self, :https, :data
#   policy.object_src  :none
#   policy.script_src  :self, :https
# Allow @vite/client to hot reload javascript changes in development
#   policy.script_src *policy.script_src, :unsafe_eval, "http://#{ ViteRuby.config.host_with_port }" if Rails.env.development?
# You may need to enable this in production as well depending on your setup.
#   policy.script_src *policy.script_src, :blob if Rails.env.test?
#   policy.style_src   :self, :https
# Allow @vite/client to hot reload style changes in development
#    policy.style_src *policy.style_src, :unsafe_inline if Rails.env.development?
# Allow @vite/client to hot reload changes in development
#    policy.connect_src *policy.connect_src, "ws://#{ ViteRuby.config.host_with_port }" if Rails.env.development?

#   # Specify URI for violation reports
#   # policy.report_uri "/csp-violation-report-endpoint"
# end

# If you are using UJS then enable automatic nonce generation
# Rails.application.config.content_security_policy_nonce_generator = -> request { SecureRandom.base64(16) }

# Set the nonce only to specific directives
# Rails.application.config.content_security_policy_nonce_directives = %w(script-src)

# Report CSP violations to a specified URI
# For further information see the following documentation:
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy-Report-Only
# Rails.application.config.content_security_policy_report_only = true
