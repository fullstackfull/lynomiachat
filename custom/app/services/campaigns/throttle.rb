# frozen_string_literal: true

# HOW FAST A CAMPAIGN MAY SEND.
#
# Until this existed, a campaign was one Sidekiq job iterating its entire audience in a bare
# synchronous loop -- no sleep, no batching, no per-second ceiling, no backoff. A ten thousand
# recipient campaign went out as fast as the provider would accept connections, which is how a
# WhatsApp sender earns a rate-limit response, a quality-rating drop and eventually a lower
# messaging tier. The quality rating and tier were already being fetched, stored and displayed
# by Whatsapp::HealthService, and read by nothing that could slow a send down.
#
# A FIXED WINDOW, NOT A LEAKY BUCKET, and the simpler one is the right one here. A campaign is
# a single-threaded loop; it does not need smoothing between concurrent producers, it needs a
# ceiling it cannot walk past. One INCR per send against a key that expires with its second is
# the whole mechanism -- no stored state to migrate, nothing to clean up, and a Redis that
# loses the key simply starts the window again.
#
# IT PACES RATHER THAN REFUSES. Hitting the ceiling sleeps until the window turns over, so a
# large campaign takes longer and still reaches everybody. Refusing instead would mean the
# recipients at the end of the audience silently never hear from the merchant, which is a
# worse outcome than a slow send and much harder to notice.
#
# AN UNREACHABLE REDIS DOES NOT STOP A CAMPAIGN. The ceiling is protection against sending too
# fast, not authorization to send at all -- consent is authorization, and consent fails closed
# in Campaigns::SendGuard. Making a cache blip halt every campaign would turn a degraded
# dependency into an outage, so a throttle that cannot read its own counter lets the send
# through and says so in the log.
module Campaigns::Throttle
  # Per account, per second. Deliberately well under WhatsApp Cloud's documented 80/s default
  # for a business-initiated burst: the ceiling exists to keep a merchant inside their tier,
  # not to find its edge.
  DEFAULT_PER_SECOND = 10
  SETTING_KEY = 'campaign_sends_per_second'
  # The longest one call will ever block. A window is a second, so this is generous; it exists
  # so a clock jump or a pathological value cannot park a worker indefinitely.
  MAX_WAIT = 2.0

  module_function

  # Called immediately before each provider call. Blocks until this send is within the
  # account's ceiling, then records it.
  #
  # @param sleeper [#call] injected so specs can assert the pause without taking it
  def pace(account, sleeper: method(:sleep))
    ceiling = ceiling_for(account)
    return true if ceiling <= 0

    waited = 0.0

    while used(account) >= ceiling && waited < MAX_WAIT
      sleeper.call(0.1)
      waited += 0.1
    end

    record(account)
    true
  rescue StandardError => e
    # A ceiling that cannot be read is not a reason to stop messaging; see the note above.
    Rails.logger.warn("[Lynomia::Campaigns] throttle unavailable for account #{account&.id}: #{e.class}")
    true
  end

  # An operator may raise or lower it per account; absent, the default applies. Zero or
  # negative turns pacing off, which is the escape hatch for a migration or a load test rather
  # than a setting anybody should leave on.
  def ceiling_for(account)
    configured = account&.settings&.dig(SETTING_KEY)
    return DEFAULT_PER_SECOND if configured.blank?

    configured.to_i
  end

  def used(account) = Redis::Alfred.get(key(account)).to_i

  def record(account)
    counter = Redis::Alfred.incr(key(account))
    # Only on the first send of a window, so the expiry is not pushed forward by later ones --
    # that would turn a one-second window into a rolling one that never resets under load.
    Redis::Alfred.expire(key(account), 2) if counter == 1
    counter
  end

  # The window is the key: a second's counter expires with that second, so there is no sweep
  # and no state older than two seconds anywhere.
  def key(account) = "CAMPAIGN_THROTTLE::#{account&.id}::#{Time.now.to_i}"
end
