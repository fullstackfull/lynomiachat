# What a platform app holds on an account, and how it is taken back.
#
# ONE IMPLEMENTATION, TWO CALLERS, ON PURPOSE. Revocation is reachable from two directions -- the app handing
# its own grant back (DELETE /platform/api/v1/account_links/:id) and the merchant withdrawing it
# (DELETE /api/v1/accounts/:id/integrations/grants/:app) -- and they must do the SAME thing. Two copies of
# this would drift, and the copy that drifted would be the merchant's, because it is the one nobody tests
# against a live integration. The only difference between the callers is who is recorded as the actor.
class Integrations::AccountGrants
  class << self
    def granted?(account, platform_app)
      platform_app.platform_app_permissibles.exists?(permissible: account)
    end

    # What this account has given away, for the merchant to look at.
    #
    # Scoped to users who are members of THIS account, so a listing cannot reveal that the app also holds
    # somebody from a workspace the viewer has nothing to do with.
    def for_account(account)
      member_ids = account.account_users.pluck(:user_id)

      PlatformAppPermissible.where(permissible: account).includes(:platform_app).filter_map do |grant|
        app = grant.platform_app
        next if app.nil?

        users = User.where(id: app.platform_app_permissibles.where(permissible_type: 'User').pluck(:permissible_id))
                    .where(id: member_ids)

        {
          platform_app_id: app.id,
          platform_app_name: app.name,
          granted_at: grant.created_at,
          signs_in_as: users.map { |user| { id: user.id, name: user.name } }
        }
      end
    end

    # Hand back everything this app holds on this account. Returns the user ids actually released.
    #
    # Idempotent: revoking a grant that is already gone releases nothing and raises nothing, which is what
    # lets a merchant click the button twice and an app retry a failed call.
    def revoke(account:, platform_app:, actor:)
      # The account grant goes first, and the order is load-bearing twice over: once it is gone the app
      # cannot reach the workspace even if a user grant somehow survived, and the "what is still linked"
      # question below must not count the account being revoked.
      platform_app.platform_app_permissibles.where(permissible: account).destroy_all

      released = release_unneeded_user_grants(platform_app)

      # A GRANT IS CHECKED AT REQUEST TIME, SO REVOKING IT DOES NOT RECALL WHAT IT ALREADY PRODUCED. An SSO
      # link minted a minute ago is a Redis key with five minutes of life of its own, and nothing above
      # touches it: without this, a link revoked for abuse still admits the holder for five more minutes.
      #
      # Swept for the users whose grants were ACTUALLY returned, and no others. USER_SSO_AUTH_TOKEN::<id>::*
      # is shared key space -- other platform apps' login links and Chatwoot's own super-admin impersonation
      # links live in it too -- so sweeping a user this app does not hold reaches outside its own
      # authorization and kills somebody else's in-flight session.
      User.where(id: released).find_each { |user| invalidate_outstanding_sso_links(user) }

      ::Integrations::AccountLinkCode.finish(account.id, 'revoked', app: platform_app)
      ::Integrations::AccountLinkCode.record_audit(
        'integrations.account_link.revoked', account, actor,
        { platform_app_id: platform_app.id, platform_app_name: platform_app.name, released_user_ids: released }
      )

      released
    end

    private

    # DERIVED FROM THE GRANTS HELD, NOT FROM THE ACCOUNT'S MEMBERSHIP. The question that matters is "which
    # User grants does this app hold, and are any of them still good for an account it still holds?" --
    # and membership is the wrong source for it twice over. It is mutable by the merchant's own admins, so a
    # granted user removed from the workspace before the revocation arrived became invisible and kept their
    # grant through a revocation that answered 200; and it includes users this app never held, which is how
    # the SSO sweep came to kill other principals' sessions.
    def release_unneeded_user_grants(platform_app)
      held_user_ids = platform_app.platform_app_permissibles
                                  .where(permissible_type: 'User')
                                  .pluck(:permissible_id)
      return [] if held_user_ids.empty?

      remaining_account_ids = platform_app.platform_app_permissibles
                                          .where(permissible_type: 'Account')
                                          .pluck(:permissible_id)

      still_needed = AccountUser.where(user_id: held_user_ids, account_id: remaining_account_ids)
                                .distinct
                                .pluck(:user_id)

      released = held_user_ids - still_needed

      platform_app.platform_app_permissibles
                  .where(permissible_type: 'User', permissible_id: released)
                  .destroy_all

      released
    end

    # There is no "all tokens for this user" accessor -- SsoAuthenticatable#invalidate_sso_auth_token takes
    # one token and the caller is normally the redeemer, who has it. Here nobody has it, so the keys are
    # swept by the pattern the concern itself writes.
    def invalidate_outstanding_sso_links(user)
      Redis::Alfred.scan_each(match: "USER_SSO_AUTH_TOKEN::#{user.id}::*") { |key| Redis::Alfred.delete(key) }
    end
  end
end
