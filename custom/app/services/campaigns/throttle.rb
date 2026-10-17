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
# OPERATIONAL PACING. IT IS NOT A PROVIDER LIMIT AND IT IS NOT A COMMERCIAL QUOTA, and
# conflating the three is the mistake this note exists to prevent:
#
#   pacing (here)        a courtesy ceiling on how fast WE dial, so a merchant stays
#                        comfortably inside their tier. Best effort. Degrades to "a short
#                        delay per send" under sustained load, and fails OPEN.
#   provider limit       the provider's own 429 and its messaging tier. Enforced by the
#                        provider; this cannot and does not substitute for it.
#   commercial quota     "this plan allows N sends this period". DOES NOT EXIST YET -- it is
#                        P5G -- and when it does it MUST NOT be routed through this module,
#                        because a quota that fails open is not a quota. It belongs with
#                        Billing::ResourceLimit.exceeded, which takes a lock and refuses.
#
# A FIXED WINDOW, NOT A LEAKY BUCKET. A campaign is a single-threaded loop; it does not need
# smoothing between concurrent producers, it needs a ceiling it does not casually walk past.
# One INCR against a key that expires with its second is the whole mechanism.
#
# THE COUNT IS THE INCR'S OWN RETURN VALUE, never a separate read. Two workers sending for one
# account would otherwise both read "9 used", both decide there was room, and both send --
# a read-then-write race that overshoots by exactly the number of concurrent workers. INCR is
# atomic and returns the post-increment value, so the decision and the record are one step.
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

  # Blocks until this send is within the account's ceiling.
  #
  # THE RETURN VALUE SAYS WHETHER TIME PASSED, and that is what it is for. A caller that
  # checked eligibility before calling this has an answer that is only as fresh as the moment
  # it asked; if this slept, a withdrawal, a kill switch or a revocation could have landed
  # during the sleep and the answer is stale. Rather than make every caller guess, this
  # reports it. `Campaigns::SendGuard.clear_to_send` is the only caller and re-asks on
  # `:waited`.
  #
  # @param sleeper [#call] injected so specs can assert the pause without taking it
  # @return [Symbol] :clear (no wait), :waited (slept, re-check eligibility),
  #   :degraded (counter unreachable, nothing paced, no wait)
  def pace(account, sleeper: method(:sleep))
    ceiling = ceiling_for(account)
    return :clear if ceiling <= 0

    waited = 0.0
    # Claim a slot in the current window. Over the ceiling means this window is spent, so wait
    # for the next one and claim there. Bounded, so a worker is never parked indefinitely.
    while claim(account) > ceiling && waited < MAX_WAIT
      sleeper.call(0.1)
      waited += 0.1
    end

    waited.zero? ? :clear : :waited
  rescue StandardError => e
    degraded(account, e)
    :degraded
  end

  # PACING FAILS OPEN, AND THAT IS ONLY SAFE BECAUSE IT IS PACING. A courtesy ceiling that
  # cannot read its counter must not halt every campaign on the installation -- that turns a
  # cache blip into an outage. Authorization is consent and it fails CLOSED in
  # Campaigns::SendGuard; a commercial quota, when one exists, must fail closed too and
  # therefore must not live here.
  #
  # Recorded as an operations signal rather than only a log line, so a degraded throttle is
  # visible on the health surface an operator actually watches instead of only to whoever
  # greps the logs afterwards.
  #
  # `source: 'campaign'`, `signal: 'sync_failed'` and `detail: { code: ... }` are not free
  # choices: Operations::Signal validates source and signal against allow-lists and
  # Operations::SignalRecorder::DETAIL_KEYS drops any other detail key. A value outside them
  # is not an error -- the recorder never raises into its caller -- it is a signal that is
  # silently never written, which is the failure mode this comment exists to prevent on the
  # next edit. (`source: 'campaigns'` and `detail: { error: ... }` were exactly that.)
  def degraded(account, error)
    Rails.logger.warn("[Lynomia::Campaigns] throttle unavailable for account #{account&.id}: #{error.class}")
    Operations::SignalRecorder.new(source: 'campaign', account: account)
                              .record('sync_failed', severity: :warning, reason: 'throttle_unavailable',
                                                     detail: { code: error.class.name })
  rescue StandardError
    nil
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

  # Atomically take a slot and report how many have been taken in this window, including this
  # one. The expiry is set only on the first claim of a window, so later claims cannot push it
  # forward and turn a one-second window into a rolling one that never resets under load.
  def claim(account)
    counter = Redis::Alfred.incr(key(account))
    Redis::Alfred.expire(key(account), 2) if counter == 1
    counter
  end

  # The window is the key: a second's counter expires with that second, so there is no sweep
  # and no state older than two seconds anywhere.
  def key(account) = "CAMPAIGN_THROTTLE::#{account&.id}::#{Time.now.to_i}"
end
