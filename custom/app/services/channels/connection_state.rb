# Whether one inbox's channel can still reach its provider, answered from facts rather than from optimism
# (docs/p10/06-channel-lifecycle-health.md).
#
# IT RETURNS P9's COMPONENT, NOT A NEW VOCABULARY. `Operations::Health::Component` already carries a status, a
# reason, how the status was established and a detail payload, and the Operations Center already renders it.
# P10 extends that rather than introducing a second set of channel states beside it. The brief's names map onto
# P9's four exactly:
#
#   CONNECTED        healthy   provider-backed, configured, nothing reported against it
#   ERROR            warning   authorization errors counted below the latch threshold, a risky provider health
#                              reading, a stored health error, or a token inside its expiry window
#   ACTION_REQUIRED  critical  the reauthorization latch is set, required credentials are missing, or a token
#                              has already expired -- somebody has to go and reconnect it
#   UNKNOWN          unknown   nothing in this fork reports this channel's health, or there is no provider to be
#                              connected to. `source_class: 'absent'` says which.
#
# DISCONNECTED IS DELIBERATELY ABSENT. A Commerce store has a real `disconnected` status column
# (Commerce::Store), and P9 reads it. A channel has nothing equivalent in this fork: an inbox either exists or
# is deleted, and no column, flag or provider field says "this channel was disconnected". Reporting it would
# mean inventing a state the repository cannot substantiate, so the honest answers are `critical` (go reconnect
# it) and `unknown` (nobody can say). Recorded in docs/p10/P10_RELEASE_GATE.md rather than faked.
#
# EVERY INPUT IS READ LIVE, which is why `source_class` is 'probed': the Redis reauthorization flag and error
# counter, the channel row's own columns, and the provider health the sync job stored. Nothing here infers,
# scores or averages. For a page of many accounts, do NOT call this per inbox -- Operations::AccountHealth uses
# the durable `operations_signals` rows instead, which is one grouped query however many inboxes exist.
class Channels::ConnectionState
  KEY = :connection

  # Instagram's own refresh service treats a token inside ten days of expiry as needing attention
  # (app/services/instagram/refresh_oauth_token_service.rb:43). Reused rather than re-chosen.
  EXPIRY_WARNING_WINDOW = 10.days

  def initialize(inbox)
    @inbox = inbox
    @channel = inbox.channel
    @capability = Channels::Capability.for_inbox(inbox)
  end

  def call
    return undescribed if @capability.nil?
    return no_provider unless @capability.provider_backed?
    return not_reported unless @capability.health_reported?

    critical_finding || warning_finding || connected
  end

  private

  def undescribed
    absent('This channel type is not described by this installation')
  end

  def no_provider
    absent('This channel has no external provider to stay connected to')
  end

  def not_reported
    absent('Nothing in this installation reports whether this connection still works')
  end

  # Order matters: the latch is the strongest statement the product makes, so it is read first and its reason is
  # the one an operator sees.
  def critical_finding
    return latched if reauthorization_required?

    missing_credentials || expired_token
  end

  def latched
    build(Operations::Health::CRITICAL, 'The channel reported an authorization error and needs to be reconnected',
          attempts: authorization_error_count)
  end

  def warning_finding
    expiring_token || risky_provider_health || counted_errors
  end

  def connected
    build(Operations::Health::HEALTHY, nil, checked: health_sources)
  end

  def reauthorization_required?
    @channel.respond_to?(:reauthorization_required?) && @channel.reauthorization_required?
  end

  def authorization_error_count
    @channel.respond_to?(:authorization_error_count) ? @channel.authorization_error_count : 0
  end

  # The only channels whose credentials can be absent while the row exists: every other channel's credential
  # columns are NOT NULL, so the database already refuses the half-configured case.
  def missing_credentials
    return unless @capability.key == :whatsapp && @channel.provider_config.blank?

    build(Operations::Health::CRITICAL, 'No provider credentials are configured for this number')
  end

  def expired_token
    expiry = token_expiry
    return if expiry.blank? || expiry > Time.current

    build(Operations::Health::CRITICAL, 'The provider authorization has expired and needs to be renewed',
          expired_at: expiry.utc.iso8601)
  end

  def expiring_token
    expiry = token_expiry
    return if expiry.blank? || expiry > EXPIRY_WARNING_WINDOW.from_now

    build(Operations::Health::WARNING, 'The provider authorization expires soon', expires_at: expiry.utc.iso8601)
  end

  # Instagram stores the access token's own expiry. TikTok's access token lasts a day and refreshes itself, so
  # the one that matters there is the refresh token -- the same distinction Tiktok::TokenService makes, which
  # latches reauthorization when the refresh token is gone.
  def token_expiry
    return unless @capability.health_source?(:token_expiry)

    @capability.key == :tiktok ? @channel.refresh_token_expires_at : @channel.expires_at
  end

  # Mirrors Whatsapp::HealthService#risky_health? exactly -- one category, not a severity split this repository
  # does not make. The service logs the same transition as a warning and stores nothing durable, which is why
  # the reading is surfaced here instead of staying in a log line.
  def risky_provider_health
    return unless @capability.health_source?(:provider_health)
    return stored_health_error if @channel.phone_number_health_error.present?

    health = @channel.phone_number_health.to_h.symbolize_keys
    return unless Whatsapp::HealthService::RISKY_QUALITY_RATINGS.include?(health[:quality_rating]) ||
                  Whatsapp::HealthService::RISKY_STATUSES.include?(health[:status])

    build(Operations::Health::WARNING, 'The provider reports this number as at risk',
          status: health[:status], quality_rating: health[:quality_rating],
          checked_at: @channel.phone_number_health_checked_at&.utc&.iso8601)
  end

  # The stored error is the provider's own message. It is not shown: it can carry a request url and an id, and
  # PART P forbids putting a provider payload in front of an agent. The fact and its time are enough to act on.
  def stored_health_error
    build(Operations::Health::WARNING, 'The last health check for this number failed',
          checked_at: @channel.phone_number_health_checked_at&.utc&.iso8601)
  end

  def counted_errors
    count = authorization_error_count
    return unless count.positive?

    build(Operations::Health::WARNING, 'The channel has reported authorization errors', attempts: count)
  end

  def health_sources
    @capability.health_sources.map(&:to_s)
  end

  def absent(reason)
    Operations::Health.absent(KEY, reason)
  end

  def build(status, reason, **detail)
    Operations::Health::Component.build(
      key: KEY, status: status, reason: reason, source_class: 'probed',
      observed_at: Time.current, detail: detail.compact
    )
  end
end
