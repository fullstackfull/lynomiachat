# frozen_string_literal: true

# Where Meta will ACTUALLY deliver this number's webhooks, and whether that is this installation.
#
# This needs its own class because the answer is not a boolean and the dashboard cannot be trusted for it. Meta
# keeps a webhook configuration at several scopes, and `GET /<phone_number_id>?fields=webhook_configuration` returns
# them together:
#
#   override_callback_uri      a PHONE-LEVEL override, set by Whatsapp::FacebookApiClient#override_phone_number_callback
#   phone_number               the effective value at the phone scope
#   whatsapp_business_account  the WABA scope
#   application                the Meta App's own configured callback
#
# A phone-level override takes PRECEDENCE over the app-level configuration, and it is not visible in the Meta App
# dashboard. So a number can be overridden to a stale URL — an old domain, a dev tunnel, a FRONTEND_URL that was
# wrong when the inbox was created — while the dashboard still shows a correct callback and looks fine. Reading the
# override back is the only way to see it, which is why the diagnosis reports a SOURCE as well as a VERDICT.
#
# Read-only: this class is handed a configuration hash and computes. It performs no request of its own.
class Whatsapp::Diagnosis::CallbackClassification
  OVERRIDE_KEY = 'override_callback_uri'
  PHONE_KEY = 'phone_number'
  APP_KEYS = %w[whatsapp_business_account application].freeze

  MATCH = 'MATCH'
  MISMATCH = 'MISMATCH'
  UNKNOWN = 'UNKNOWN'

  PHONE_LEVEL_OVERRIDE = 'PHONE_LEVEL_OVERRIDE'
  APP_LEVEL_CALLBACK = 'APP_LEVEL_CALLBACK'

  MISMATCH_NOTE = 'Meta is delivering this number\'s webhooks somewhere other than this installation, so no inbound ' \
                  'message can arrive however healthy the rest of the configuration is. Re-register through ' \
                  'Whatsapp::WebhookSetupService#register_callback after confirming FRONTEND_URL is the public URL; ' \
                  'do not edit the override by hand.'

  UNKNOWN_NOTE = 'Meta did not return a webhook configuration for this number, so the effective callback is ' \
                 'UNPROVEN — treat it as unchecked, not as correct. The BLOCKED line above names the Meta error.'

  attr_reader :expected, :configuration

  # @param expected [String] the callback URL this installation serves for the number
  # @param configuration [Hash, nil] Meta's `webhook_configuration` object, or nil when the read failed
  def initialize(expected:, configuration:)
    @expected = expected.to_s
    @configuration = (configuration || {}).to_h
  end

  # @return [String] PHONE_LEVEL_OVERRIDE, APP_LEVEL_CALLBACK or UNKNOWN
  def source
    return PHONE_LEVEL_OVERRIDE if override.present?
    return APP_LEVEL_CALLBACK if app_level.present?

    UNKNOWN
  end

  # @return [String] MATCH, MISMATCH or UNKNOWN
  def verdict
    return UNKNOWN if effective.blank? || expected.blank?

    effective == expected ? MATCH : MISMATCH
  end

  # The one token to print: a verdict, qualified by the scope that produced it.
  def to_s
    source == UNKNOWN ? verdict : "#{verdict} (#{source})"
  end

  def note
    case verdict
    when MISMATCH then MISMATCH_NOTE
    when UNKNOWN then UNKNOWN_NOTE
    end
  end

  # The override wins when both exist, because that is Meta's precedence.
  def effective
    override.presence || app_level
  end

  def override
    @override ||= configuration[OVERRIDE_KEY].presence || configuration[PHONE_KEY].presence
  end

  def app_level
    @app_level ||= APP_KEYS.filter_map { |key| configuration[key].presence }.first
  end

  # Only ever the scheme, host, port and path: an override URI carries its verify token in the query string, and
  # this report is meant to be pasted into an issue.
  def self.safe(value)
    return '<none>' if value.blank?

    uri = URI.parse(value.to_s)
    [uri.scheme, uri.host, uri.port, uri.path].compact.join(' ')
  rescue URI::InvalidURIError
    '<unparseable>'
  end
end
