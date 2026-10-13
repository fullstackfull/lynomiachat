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
# User grant is what lets it mint an SSO link, because /users/:id/login is permissible-checked on the USER. The
# user granted is the administrator who authorized it and nobody else: the app cannot choose, cannot name a
# different user, and cannot widen the grant afterwards.
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

    account, user = resolve_authorizer(attempt)
    return render_invalid('The code is no longer valid for this account') if account.nil?

    grant(account, user)
    record_grant(account, user)

    render json: {
      account_id: account.id, account_name: account.name,
      user_id: user.id, user_name: user.name
    }, status: :created
  end

  def destroy
    candidate_user_ids = @resource.account_users.pluck(:user_id)

    # The account grant goes first, and the order is load-bearing twice over: once it is gone the app cannot
    # reach the workspace even if a user grant somehow survived, and the "what is still linked" question below
    # must not count the account being revoked.
    @platform_app.platform_app_permissibles.where(permissible: @resource).destroy_all

    # A USER GRANT CAN BE SHARED. One person can administer two accounts and authorize this app on both, and
    # both links then rest on the same single User permissible -- there is one row per (app, user), not one per
    # link. Dropping every member of the revoked account would therefore silently break SSO for the OTHER
    # account, which is still linked and still paid for. So a user keeps their grant while any account this app
    # still holds has them as a member.
    #
    # Found by the spec, not by inspection: an earlier version of this method claimed in its own comment to do
    # this and did not.
    remaining_account_ids = @platform_app.platform_app_permissibles
                                         .where(permissible_type: 'Account')
                                         .pluck(:permissible_id)

    still_needed = AccountUser.where(user_id: candidate_user_ids, account_id: remaining_account_ids)
                              .pluck(:user_id)
                              .uniq

    @platform_app.platform_app_permissibles
                 .where(permissible_type: 'User', permissible_id: candidate_user_ids - still_needed)
                 .destroy_all

    # A GRANT IS CHECKED AT REQUEST TIME, SO REVOKING IT DOES NOT RECALL WHAT IT ALREADY PRODUCED. An SSO
    # link minted a minute ago is a Redis key with a five-minute life of its own, and nothing above touches
    # it: without this, a link revoked for abuse still lets the holder in for up to five more minutes. Only
    # the users who actually lost their grant are swept -- a user kept for another live link keeps their
    # session too.
    revoked_user_ids = candidate_user_ids - still_needed
    User.where(id: revoked_user_ids).find_each { |revoked| invalidate_outstanding_sso_links(revoked) }

    ::Integrations::AccountLinkCode.finish(@resource.id, 'revoked')
    ::Integrations::AccountLinkCode.record_audit(
      'integrations.account_link.revoked', @resource, nil,
      { platform_app_id: @platform_app.id, platform_app_name: @platform_app.name }
    )

    head :ok
  end

  private

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

  def record_grant(account, user)
    ::Integrations::AccountLinkCode.finish(account.id, 'connected')
    ::Integrations::AccountLinkCode.record_audit(
      'integrations.account_link.granted', account, user,
      { platform_app_id: @platform_app.id, platform_app_name: @platform_app.name, user_id: user.id }
    )
  end

  # There is no "all tokens for this user" accessor -- SsoAuthenticatable#invalidate_sso_auth_token takes one
  # token and the caller is normally the redeemer, who has it. Here nobody has it, so the keys are swept by
  # the pattern the concern itself writes (Redis::RedisKeys::USER_SSO_AUTH_TOKEN, 'USER_SSO_AUTH_TOKEN::%<user_id>d::%<token>s').
  def invalidate_outstanding_sso_links(user)
    Redis::Alfred.scan_each(match: "USER_SSO_AUTH_TOKEN::#{user.id}::*") { |key| Redis::Alfred.delete(key) }
  end

  # find_or_create_by, so re-redeeming after a lost answer lands in the same place rather than raising on the
  # unique index. Both rows or neither: a half-granted link would read as connected while SSO failed.
  def grant(account, user)
    ActiveRecord::Base.transaction do
      @platform_app.platform_app_permissibles.find_or_create_by!(permissible: account)
      @platform_app.platform_app_permissibles.find_or_create_by!(permissible: user)
    end
  end

  def set_resource
    @resource = Account.find(params[:id])
  end
end
