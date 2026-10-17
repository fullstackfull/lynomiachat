# Spending the proof a merchant minted inside their own account.
#
#   POST   /platform/api/v1/account_links        redeem a code; returns the account it proves
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
# THE GRANT IS THE ACCOUNT, AND NOTHING ELSE. Redemption hands the app a permissible on the workspace and
# stops there. It does NOT hand back the authorizing administrator's own identity: generate_sso_link mints
# an UNSCOPED Devise session for a human, so granting it would cash a proof about ONE account in for the
# ability to act as that person in every account they belong to. Measured, not reasoned.
#
# AN EARLIER VERSION CREATED A SHARED SERVICE USER HERE and made it an administrator of the workspace on
# every link. That closed the impersonation but bought two problems of its own: one identity for all of a
# merchant's staff, so nothing done through the integration was attributable to the person who did it, and
# a default administrator where most of those people should be agents.
#
# Both are what the per-user identity model replaces. The integration creates one Lynomia user per person
# per workspace through the ordinary platform API, with the role that person actually holds, and mints an
# ACCOUNT-SCOPED SSO link for it (GET /platform/api/v1/users/:id/login?account_id=). So this endpoint
# grants the account; who signs in, as whom, and with what role is decided per person afterwards and is
# visible in the merchant's own team list.
#
# `create` is NOT behind validate_platform_app_permissible. That is deliberate and it is the only route in this
# namespace where its absence is a decision rather than an inherited default -- an app cannot hold a permissible
# on an account it has not linked yet, so requiring one would make linking impossible. The code is the
# authorization. `destroy` is the opposite: it acts on an account the app already holds, so it uses
# PlatformController's inherited set_resource + validate_platform_app_permissible chain unchanged.
class Platform::Api::V1::AccountLinksController < PlatformController
  def create
    return render_invalid('code is required', 'missing_code') if params[:code].blank?

    attempt = ::Integrations::AccountLinkCode.redeem(params[:code], platform_app: @platform_app)

    # One answer for "no such code", "already used" and "expired", on purpose: telling them apart turns this
    # into an oracle for whether a given string was ever a real code.
    return render_invalid('Invalid or expired code', 'invalid_code') if attempt == :unknown

    # A REAL CODE FOR SOMEBODY ELSE. Said plainly rather than hidden behind the generic answer, because the
    # app hearing it cannot act on the difference -- it has no code either way -- while the merchant who
    # pasted it into the wrong field is the one who needs to know they did. Nothing is consumed: the code is
    # still live for the integration it was minted for.
    if attempt == :wrong_app
      return render json: { error: 'This code was issued for a different integration',
                            error_code: 'wrong_platform_app' },
                    status: :unprocessable_entity
    end

    account, authorizer = resolve_authorizer(attempt)
    return render_invalid('The code is no longer valid for this account', 'invalid_code') if account.nil?

    grant_one(account)
    record_grant(account, authorizer)

    render json: {
      account_id: account.id, account_name: account.name,
      authorized_by_user_id: authorizer.id, authorized_by_name: authorizer.name
    }, status: :created
  end

  def destroy
    ::Integrations::AccountGrants.revoke(account: @resource, platform_app: @platform_app, actor: @platform_app)

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

  # error_code IS A CONTRACT, THE SENTENCE IS NOT. The integration on the other side has to tell a merchant
  # which mistake they made -- a dead code and a code for somebody else's integration need different advice --
  # and matching on English prose would break the day somebody rewords it. The client reads the code and
  # writes its own sentence; the prose stays for people reading the response directly.
  def render_invalid(message, error_code)
    render json: { error: message, error_code: error_code }, status: :unprocessable_entity
  end

  def record_grant(account, authorizer)
    ::Integrations::AccountLinkCode.finish(account.id, 'connected', app: @platform_app)
    ::Integrations::AccountLinkCode.record_audit(
      'integrations.account_link.granted', account, authorizer,
      { platform_app_id: @platform_app.id, platform_app_name: @platform_app.name,
        authorized_by_user_id: authorizer.id }
    )
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
