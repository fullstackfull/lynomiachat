# Spending the proof a merchant minted inside their own account.
#
#   POST   /platform/api/v1/account_links        redeem a code; returns the account and user it proves
#   DELETE /platform/api/v1/account_links/:id    hand every grant on that account back (:id is the account)
#
# WHY THIS ENDPOINT EXISTS AT ALL. Linking an account a platform app did not create is the one thing the
# platform API could not previously do safely. The only available primitive was `POST /platform/api/v1/users`,
# which resolves `User.from_email(...) || User.new(...)` and then grants the caller a permissible on whatever it
# resolved -- handed a real customer's address that is not a link, it is a silent account takeover. An app also
# cannot look an account up to check first, because validate_platform_app_permissible confines it to accounts it
# already holds. So every email- or id-based scheme ends in the same place: the CLAIMANT asserting who they are.
#
# Here the claimant asserts nothing. They present a string that could only have come from somebody who
# authenticated to Lynomia as an administrator of the account (Integrations::AccountLinkCode, minted at
# POST /api/v1/accounts/:id/integrations/account_link_code). The app never names an account, never sends an
# email, and cannot enumerate: 80 bits, one hour, single use, HMAC at rest.
#
# THE ROLE IS RE-CHECKED AT REDEMPTION, not trusted from the code. A code lives an hour; an administrator can be
# demoted or removed inside an hour, and a bearer token minted before a dismissal must not survive it.
#
# TWO GRANTS, AND BOTH ARE NEEDED. The Account grant is what lets the app read and manage the workspace. The
# User grant is what lets it mint an SSO link, because /users/:id/login is permissible-checked on the USER.
#
# THE USER GRANTED IS A SERVICE USER, NOT THE PERSON WHO AUTHORIZED IT, AND THAT IS THE WHOLE REASON THIS
# METHOD HAS A find_or_create_service_user! IN IT. generate_sso_link mints an unscoped Devise session for a
# human (app/models/concerns/sso_authenticatable.rb -- /app/login?email=...&sso_auth_token=..., with no account
# in it). Granting the administrator's own identity therefore cashes a proof about ONE account in for the
# ability to act as that person in EVERY account they belong to. Measured, not reasoned: with a grant on a
# human who administers account L and is an agent of unrelated account S, the redeemed session read
# /api/v1/accounts/S/conversations and /api/v1/accounts/S/contacts successfully. Account S consented to
# nothing and the app holds no grant on it.
#
# So the administrator's consent is recorded and their identity is left alone. The grant goes to a user that
# exists only for this (app, account) pair, is a member of that account and nothing else, and is the same
# shape the provisioning flow already uses. It appears in the merchant's team list under its own name, which
# is the honest version of what is happening: an integration has access, not a colleague.
#
# THE SERVICE ADDRESS CANNOT BE PRE-REGISTERED, which matters because resolving a user by address is the
# documented takeover primitive. The local part is an HMAC under this installation's secret, so it cannot be
# guessed; and if an address somehow does already exist, a user without this app's marker in its
# custom_attributes is REFUSED rather than adopted -- custom_attributes is only writable through the platform
# API, so a self-registered account can never carry it.
#
# `create` is NOT behind validate_platform_app_permissible. That is deliberate and it is the only route in this
# namespace where its absence is a decision rather than an inherited default -- an app cannot hold a permissible
# on an account it has not linked yet, so requiring one would make linking impossible. The code is the
# authorization. `destroy` is the opposite: it acts on an account the app already holds, so it uses
# PlatformController's inherited set_resource + validate_platform_app_permissible chain unchanged.
class Platform::Api::V1::AccountLinksController < PlatformController
  def create
    return render_invalid('code is required') if params[:code].blank?

    attempt = ::Integrations::AccountLinkCode.redeem(params[:code])

    # One answer for "no such code", "already used" and "expired", on purpose: telling them apart turns this
    # into an oracle for whether a given string was ever a real code.
    return render_invalid('Invalid or expired code') if attempt.blank?

    account, authorizer = resolve_authorizer(attempt)
    return render_invalid('The code is no longer valid for this account') if account.nil?

    service_user = find_or_create_service_user!(account)
    return render_invalid('This workspace cannot be connected automatically') if service_user.nil?

    grant(account, service_user)
    record_grant(account, authorizer, service_user)

    render json: {
      account_id: account.id, account_name: account.name,
      user_id: service_user.id, user_name: service_user.name
    }, status: :created
  end

  def destroy
    # The account grant goes first, and the order is load-bearing twice over: once it is gone the app cannot
    # reach the workspace even if a user grant somehow survived, and the "what is still linked" question below
    # must not count the account being revoked.
    @platform_app.platform_app_permissibles.where(permissible: @resource).destroy_all

    released = release_unneeded_user_grants

    # A GRANT IS CHECKED AT REQUEST TIME, SO REVOKING IT DOES NOT RECALL WHAT IT ALREADY PRODUCED. An SSO link
    # minted a minute ago is a Redis key with five minutes of life of its own, and nothing above touches it:
    # without this, a link revoked for abuse still admits the holder for five more minutes.
    #
    # Swept for the users whose grants were ACTUALLY returned, and no others. USER_SSO_AUTH_TOKEN::<id>::* is
    # shared key space -- other platform apps' login links and Chatwoot's own super-admin impersonation links
    # live in it too -- so sweeping a user this app does not hold reaches outside its own authorization and
    # kills somebody else's in-flight session. An earlier version derived the sweep from the account's
    # membership and did exactly that.
    User.where(id: released).find_each { |revoked| invalidate_outstanding_sso_links(revoked) }

    ::Integrations::AccountLinkCode.finish(@resource.id, 'revoked', app: @platform_app)
    # The actor is the app, not nobody. audits.user is polymorphic and Billing::OverrideGrant already stores a
    # PlatformApp there, so capture_actor_name falls through to its name and the account's audit trail can
    # answer "who disconnected our integration" through its own actor filter.
    ::Integrations::AccountLinkCode.record_audit(
      'integrations.account_link.revoked', @resource, @platform_app,
      { platform_app_id: @platform_app.id, platform_app_name: @platform_app.name, released_user_ids: released }
    )

    head :ok
  end

  private

  # Hand back every User grant this app can no longer use, and report which.
  #
  # DERIVED FROM THE GRANTS HELD, NOT FROM THE ACCOUNT'S MEMBERSHIP. The question that matters is "which User
  # grants does this app hold, and are any of them still good for an account it still holds?" -- and
  # membership is the wrong source for it twice over. It is mutable by the merchant's own admins, so a granted
  # user removed from the workspace before the revocation arrives became invisible and kept their grant
  # through a revocation that answered 200; and it includes users this app never held, which is how the SSO
  # sweep came to kill other principals' sessions.
  #
  # The rule is now simply: a held User grant survives only while some account this app still holds has that
  # user as a member. A service user belongs to exactly one account, so revoking its account releases it;
  # another link's service user is a member of that link's account, so it is kept.
  def release_unneeded_user_grants
    held_user_ids = @platform_app.platform_app_permissibles
                                 .where(permissible_type: 'User')
                                 .pluck(:permissible_id)
    return [] if held_user_ids.empty?

    remaining_account_ids = @platform_app.platform_app_permissibles
                                         .where(permissible_type: 'Account')
                                         .pluck(:permissible_id)

    still_needed = AccountUser.where(user_id: held_user_ids, account_id: remaining_account_ids)
                              .distinct
                              .pluck(:user_id)

    released = held_user_ids - still_needed

    @platform_app.platform_app_permissibles
                 .where(permissible_type: 'User', permissible_id: released)
                 .destroy_all

    released
  end

  # The membership is re-read NOW, not taken from the code. Deleted account, deleted user, membership removed,
  # or demoted to agent -- all land here, and all are refused. The code has already been burned by redeem at
  # this point, which is the right way round: a code minted before a dismissal must not survive it, and must
  # not be retryable until the author happens to be promoted again.
  def resolve_authorizer(attempt)
    account = Account.find_by(id: attempt['account_id'])
    user = User.find_by(id: attempt['user_id'])
    account_user = account && user ? account.account_users.find_by(user_id: user.id) : nil

    account_user&.administrator? ? [account, user] : [nil, nil]
  end

  def render_invalid(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  # The actor on the audit row is the human who authorized it -- they are the one who made the decision, even
  # though the grant went to the service user. Both ids are recorded so the row answers "who agreed" and "what
  # can now sign in" separately.
  def record_grant(account, authorizer, service_user)
    ::Integrations::AccountLinkCode.finish(account.id, 'connected', app: @platform_app)
    ::Integrations::AccountLinkCode.record_audit(
      'integrations.account_link.granted', account, authorizer,
      {
        platform_app_id: @platform_app.id, platform_app_name: @platform_app.name,
        authorized_by_user_id: authorizer.id, service_user_id: service_user.id
      }
    )
  end

  # The user this app signs in as for this account. One per (app, account), created on first link and reused
  # afterwards, so re-linking does not accumulate members.
  def find_or_create_service_user!(account)
    email = service_email(account)
    existing = User.from_email(email)

    if existing
      # An address that already exists and is not ours is not something to adopt. Only the platform API can
      # write custom_attributes, so a self-registered user can never carry this marker.
      return nil unless existing.custom_attributes.is_a?(Hash) &&
                        existing.custom_attributes['platform_app_id'] == @platform_app.id

      user = existing
    else
      user = User.new(
        name: "#{@platform_app.name.presence || "App ##{@platform_app.id}"} Integration",
        email: email,
        # Never used and never stored: this user signs in only through a one-time SSO link.
        # It exists because Devise requires one, and it must satisfy the installation's
        # complexity policy (upper, lower, digit, symbol) or save! fails validation.
        password: service_user_password,
        custom_attributes: { 'platform_app_id' => @platform_app.id, 'linked_account_id' => account.id }
      )
      user.skip_confirmation!
      user.save!
    end

    # A member of THIS account and no other, which is the scope the merchant actually consented to.
    membership = account.account_users.find_or_initialize_by(user_id: user.id)
    membership.update!(role: :administrator)

    user
  end

  def service_user_password
    "#{SecureRandom.alphanumeric(32)}aZ9!"
  end

  # Unguessable: an attacker who could predict this address could pre-register it and be adopted. Derived from
  # the installation secret, so it is stable across restarts and different on every installation.
  def service_email(account)
    digest = OpenSSL::HMAC.hexdigest(
      'SHA256',
      Rails.application.key_generator.generate_key('integrations_account_link_service_user'),
      "#{@platform_app.id}:#{account.id}"
    )

    "app-#{@platform_app.id}-account-#{account.id}-#{digest[0, 16]}@platform-app.invalid"
  end

  # There is no "all tokens for this user" accessor -- SsoAuthenticatable#invalidate_sso_auth_token takes one
  # token and the caller is normally the redeemer, who has it. Here nobody has it, so the keys are swept by
  # the pattern the concern itself writes (Redis::RedisKeys::USER_SSO_AUTH_TOKEN, 'USER_SSO_AUTH_TOKEN::%<user_id>d::%<token>s').
  def invalidate_outstanding_sso_links(user)
    Redis::Alfred.scan_each(match: "USER_SSO_AUTH_TOKEN::#{user.id}::*") { |key| Redis::Alfred.delete(key) }
  end

  # Both rows or neither: a half-granted link would read as connected while SSO failed.
  def grant(account, user)
    ActiveRecord::Base.transaction do
      grant_one(account)
      grant_one(user)
    end
  end

  # THE RESCUE IS THE CONCURRENT CASE, AND IT IS THE ONLY WAY TO COVER BOTH.
  #
  # Sequentially, find_or_create_by's SELECT finds the existing row and nothing is inserted -- which is what
  # makes a re-redemption after a lost answer a no-op. Concurrently, that SELECT cannot see an uncommitted
  # insert from the other request, so both decide to create and the loser hits unique_permissibles_index.
  # PlatformController rescues RecordInvalid but NOT RecordNotUnique, so without this that is a 500 on a code
  # redeem has already burned: nothing useful to show the merchant and nothing to retry with.
  #
  # create_or_find_by is the obvious alternative and is wrong here: PlatformAppPermissible ALSO declares a
  # model-level uniqueness validation, which fires on the insert-first path and raises RecordInvalid before
  # the database is ever consulted -- a plain 422 on an ordinary second link. Measured, not guessed.
  #
  # The inner savepoint is not decoration either: on Postgres a failed statement poisons the surrounding
  # transaction until it is rolled back, so the rescue would have nothing usable to re-read with.
  def grant_one(resource)
    ActiveRecord::Base.transaction(requires_new: true) do
      @platform_app.platform_app_permissibles.find_or_create_by!(permissible: resource)
    end
  rescue ActiveRecord::RecordNotUnique
    @platform_app.platform_app_permissibles.find_by!(permissible: resource)
  end

  def set_resource
    @resource = Account.find(params[:id])
  end
end
