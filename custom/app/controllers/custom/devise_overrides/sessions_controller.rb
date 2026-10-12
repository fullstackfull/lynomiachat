# B14 -- a user signs in, and signs out (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# Recorded here rather than from the User model, for two reasons. A sign-in is not a change to any row, so the
# `audited` macro has nothing to observe; and a user belongs to several accounts, so a row written from the
# model could not say which account's trail it belongs on. The session knows both.
#
# `render_create_success` is the single point every successful sign-in passes through -- password, SSO token and
# MFA all render through it -- so hooking it records each of them once and records no failed attempt. A failed
# sign-in is deliberately not recorded (package B §9).
#
# Sign-out comes through upstream's own block: DeviseTokenAuth removes `@resource` before rendering, and yields
# the user to a block instead, which is the only place it is still available.
#
# `user:sign_in` and `user:sign_out` are the browser's own labels for these two events
# (app/javascript/dashboard/helper/auditlogHelper.js:22-23), which is why the action is a verb rather than one
# of the gem's create/update/destroy.
module Custom::DeviseOverrides::SessionsController
  SIGN_IN = 'sign_in'.freeze
  SIGN_OUT = 'sign_out'.freeze

  def render_create_success
    super
    record_session_event(@resource, SIGN_IN)
  end

  def destroy
    super { |user| record_session_event(user, SIGN_OUT) }
  end

  private

  # One row, on the trail of the account the session is for. A sign-in is not an account-scoped action, so an
  # account has to be chosen: the most recently active membership is the account the dashboard restores the
  # person into, and it is the same rule the product already uses to decide which account a user is "in"
  # (app/views/api/v1/models/_user.json.jbuilder:5). Writing a row per membership instead would make recording
  # cost grow with the number of accounts a person belongs to, which package B §8 criterion 9 forbids.
  def record_session_event(user, action)
    return if user.blank?

    membership = session_account_user(user)
    return if membership.blank?

    # `as_user`, because this is the one capture point whose actor the request context does not hold: the
    # devise controllers are skipped by `set_current_user`, and by the time a sign-out renders, upstream has
    # already removed the resource.
    Custom::AuditLog.as_user(user) do
      AuditTrail::Event.record(
        action: action, auditable: user, account: membership.account,
        comment: "user.#{action}", changes: { account_id: membership.account_id }
      )
    end
  end

  def session_account_user(user)
    user.account_users.order(Arel.sql('active_at DESC NULLS LAST'), id: :asc).first
  end
end
