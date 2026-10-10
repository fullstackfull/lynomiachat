# frozen_string_literal: true

# Bandwidth callback authentication (docs/p11/00-p10-security-closure.md, SC1).
#
# Basic auth is the ONLY authentication Bandwidth documents for callbacks, and the credentials are configured
# on the Messaging Application in the Bandwidth dashboard
# (https://dev.bandwidth.com/guides/callbacks/callbacks.html). There is no signature or HMAC header to verify,
# so there is nothing else to check and nothing to invent.
#
# The credentials live in `provider_config` beside the API key the channel already stores. A channel with none
# configured cannot authenticate anything, so `callback_credentials_match?` answers false and the webhook
# fails closed.
module Custom::Channel::Sms
  CALLBACK_USERNAME_KEY = 'callback_username'
  CALLBACK_PASSWORD_KEY = 'callback_password'

  def callback_username
    provider_config[CALLBACK_USERNAME_KEY].to_s
  end

  def callback_password
    provider_config[CALLBACK_PASSWORD_KEY].to_s
  end

  def callback_credentials_configured?
    callback_username.present? && callback_password.present?
  end

  # `&` rather than `&&`: both comparisons always run, so the answer does not reveal which half matched.
  # `secure_compare` digests its arguments first, so differing lengths are safe.
  def callback_credentials_match?(username, password)
    return false unless callback_credentials_configured?

    ActiveSupport::SecurityUtils.secure_compare(username.to_s, callback_username) &
      ActiveSupport::SecurityUtils.secure_compare(password.to_s, callback_password)
  end
end
