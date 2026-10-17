# One-time codes that prove a merchant controls the Lynomia account an external platform wants to link.
#
# THE PROBLEM THIS SOLVES. A platform app that wants to link an account it did not create has no honest way to
# establish that the person asking actually controls it. It cannot look the account up -- the platform API
# confines it to its own permissibles -- and it must not go by email: `POST /platform/api/v1/users` resolves
# `User.from_email(...) || User.new(...)` and grants the caller a permissible on whatever it finds, so an email
# that already belongs to somebody is not a link, it is a takeover. Any scheme where the CLAIMANT supplies the
# identifier is the same mistake wearing a different hat.
#
# So the proof is minted here, on the side that can actually check. An administrator of the account signs in to
# Lynomia -- which is the authentication -- and asks for a code. They hand it to the external platform, which
# redeems it server to server. The claimant never names an account, so there is nothing to point at a workspace
# they cannot already sign in to, and nothing an attacker can guess that is cheaper than the code itself.
#
# WHAT A REDEEMED CODE MEANS, precisely: "at the moment it was created, this user was an administrator of this
# account, and whoever holds this string got it from them". Redemption re-checks the administrator role rather
# than trusting the creation-time snapshot, because an administrator who was demoted or removed in between must
# not still be able to authorize an app -- a code is a bearer token and the hour it lives is long enough for a
# dismissal to matter.
#
# Modelled on Commerce::Salla::ConnectionCode, deliberately and almost line for line: same alphabet, same
# entropy, same HMAC-and-forget storage, same single-use read. That service solves the identical problem in the
# opposite direction and has been in production; this is not the place to invent a second scheme.
class Integrations::AccountLinkCode
  TTL = 1.hour
  PROGRESS_TTL = 1.day
  # 32 symbols without 0/O/1/I, so 16 of them are 80 random bits. Merchants read these aloud to support.
  ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'.freeze
  LENGTH = 16

  class << self
    # Replaces the account's previous code, so a merchant who generated one by mistake has not left a second
    # live credential behind. Returns the plaintext ONCE; only its HMAC is kept.
    #
    # `platform_app` IS REQUIRED, AND THAT IS THE WHOLE POINT OF THE AUDIENCE. A code with no audience is a
    # bearer token for whoever presents it first: on an installation carrying more than one app, a merchant
    # pasting their code into the wrong integration's field handed that app a working grant, while the
    # intended one was told only "Invalid or expired code" -- indistinguishable from a typo. Verified by
    # execution before this existed. The merchant now names the integration when they mint, and redemption
    # refuses anybody else.
    def create(account:, user:, platform_app:)
      code = Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.length)] }.join
      expires_at = TTL.from_now.utc.iso8601
      code_digest = digest(code)

      # THE ORDER AND THE GETSET ARE BOTH LOAD-BEARING.
      #
      # Read-then-delete-then-write across four round trips is not a replacement, it is a race: two
      # administrators clicking Generate at the same moment both read the same previous digest, both delete
      # it, and both write their own -- leaving TWO live codes while progress records only one. The digest of
      # the other is lost, so no later create can ever delete it and it stays redeemable for the rest of its
      # hour. The merchant, shown one code, believes regenerating killed the first. It did not.
      #
      # Writing the new code BEFORE swapping progress means a redemption in the gap finds a live code rather
      # than nothing. GETSET then swaps progress atomically and returns whatever was there, so each racer
      # deletes exactly the code it displaced: A displaces the old one, B displaces A's, and the one left live
      # is the one progress names. GETSET drops the key's TTL, so it is reapplied.
      payload = { account_id: account.id, user_id: user.id, platform_app_id: platform_app.id }
      Redis::Alfred.setex(code_key(code_digest), payload.to_json, TTL)
      retire_displaced_code(account.id, code_digest, expires_at, platform_app)

      record_audit('integrations.account_link.code_issued', account, user,
                   { platform_app_id: platform_app.id, platform_app_name: platform_app.name })

      { code: code.scan(/.{4}/).join('-'), expires_at: expires_at,
        platform_app: { id: platform_app.id, name: platform_app.name } }
    end

    # The payload the code was minted for, or a symbol saying why not:
    #   :unknown    no such code, already used, or expired -- one answer for all three, deliberately
    #   :wrong_app  a real, live code, but minted for a DIFFERENT integration
    #
    # THE AUDIENCE IS CHECKED BEFORE THE CODE IS CONSUMED, which is why this is no longer one MULTI.
    # Burning a code on a mismatched redemption would let any app on the installation destroy a merchant's
    # code by guessing at it -- the legitimate integration would then fail, and the merchant would be told
    # their own code was invalid.
    #
    # SINGLE USE SURVIVES THE SPLIT, and not by luck: DEL returns how many keys it removed, so of two
    # correctly-addressed redemptions racing on one string exactly one sees 1 and the other sees 0. The read
    # before it can be stale; the delete cannot. (This is also why it is not WATCH/MULTI: MockRedis makes
    # WATCH a no-op, so a CAS here would be untestable, while DEL's count is real in both.)
    #
    # The merchant types this, so case, spaces and dashes do not matter.
    def redeem(raw_code, platform_app:)
      return :unknown if raw_code.blank?

      key = code_key(digest(raw_code.to_s.upcase.delete('^A-Z0-9')))
      value = Redis::Alfred.get(key)
      return :unknown if value.nil?

      attempt = JSON.parse(value)

      # NO SILENT FALLBACK. A code with no audience cannot be matched by anybody -- it is either a code from
      # before audiences existed (one TTL of overlap) or a forgery, and admitting it would reinstate exactly
      # the bearer semantics the audience replaces.
      return :wrong_app unless attempt['platform_app_id'] == platform_app.id

      return :unknown unless Redis::Alfred.delete(key).to_i == 1

      attempt.tap { finish(attempt['account_id'], 'claimed') }
    end

    # Swap progress to the new code atomically and delete whatever it displaced. GETSET is what makes two
    # racers each retire exactly the code they replaced -- A retires the old one, B retires A's -- instead of
    # both retiring the same one and leaving two live. It drops the key's TTL, so it is reapplied.
    def retire_displaced_code(account_id, code_digest, expires_at, platform_app)
      progress = { 'status' => 'waiting', 'digest' => code_digest, 'expires_at' => expires_at,
                   'intended_app' => platform_app.name.presence || "App ##{platform_app.id}" }
      displaced = Redis::Alfred.with { |conn| conn.getset(progress_key(account_id), progress.to_json) }
      Redis::Alfred.expire(progress_key(account_id), PROGRESS_TTL.to_i)

      displaced_digest = displaced.present? ? JSON.parse(displaced)['digest'] : nil
      Redis::Alfred.delete(code_key(displaced_digest)) if displaced_digest.present?
    end

    # `app` names the platform app that acted, and it is recorded so the merchant can SEE WHICH INTEGRATION
    # took their code. A code is not bound to an app at mint time -- the merchant has no way to say which one
    # they mean -- so on an installation carrying more than one, pasting it into the wrong integration's field
    # hands that app a working grant while the intended one is told only "Invalid or expired code". Verified
    # by execution during review: the unintended app redeemed, held the grant, and minted a session, and
    # nothing anywhere said so. Naming the app does not prevent that; it makes it visible, which is the
    # difference between a mistake somebody can undo and one nobody can see.
    def finish(account_id, status, app: nil)
      current = progress(account_id)
      return if current.nil?

      update = { 'status' => status }
      update['connected_app'] = app.name.presence || "App ##{app.id}" if app

      save_progress(account_id, current.merge(update))
    end

    # What the merchant's settings page shows: none | waiting | expired | claimed | connected | revoked.
    def status(account)
      current = progress(account.id)
      return { status: 'none' } if current.nil?

      status = current['status'] == 'waiting' && Time.iso8601(current['expires_at']).past? ? 'expired' : current['status']
      { status: status, expires_at: current['expires_at'], connected_app: current['connected_app'],
        intended_app: current['intended_app'] }.compact
    end

    # Exposed so the redeeming controller can audit under the same event vocabulary.
    def record_audit(event, account, user, changes = {})
      Rails.logger.info("[Integrations] #{event} account_id=#{account.id} user_id=#{user&.id}")
      Custom::AuditLog.create!(
        auditable: account, associated: account, user: user,
        action: 'update', comment: event, audited_changes: changes
      )
    end

    private

    def digest(code)
      OpenSSL::HMAC.hexdigest('SHA256', Rails.application.key_generator.generate_key('integrations_account_link_code'), code)
    end

    # The prefix is cleared wholesale by spec/support/integrations_account_link.rb between examples. Redis is a
    # MockRedis in test and is never flushed globally, so a new prefix that nothing clears leaks across examples
    # and makes the suite order-dependent.
    def code_key(digest) = "INTEGRATIONS::ACCOUNT_LINK::CODE::#{digest}"

    def progress_key(account_id) = "INTEGRATIONS::ACCOUNT_LINK::ACCOUNT::#{account_id}"

    def progress(account_id)
      JSON.parse(Redis::Alfred.get(progress_key(account_id)) || 'null')
    end

    def save_progress(account_id, progress)
      Redis::Alfred.setex(progress_key(account_id), progress.to_json, PROGRESS_TTL)
    end
  end
end
