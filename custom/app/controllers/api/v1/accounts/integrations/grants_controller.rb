# What this workspace has given away, and taking it back.
#
#   GET    /api/v1/accounts/:account_id/integrations/grants       which integrations hold access, and since when
#   DELETE /api/v1/accounts/:account_id/integrations/grants/:id   hand one back (:id is the platform app)
#
# WHY A MERCHANT-FACING SURFACE EXISTS AT ALL. Until now a grant could only be revoked by the app that held
# it, calling DELETE on itself. That is the wrong party: the merchant consented, the merchant's workspace is
# the thing at stake, and an integration that has misbehaved -- or one that simply received a code pasted into
# the wrong field -- is the least likely to volunteer. An access nobody but its holder can withdraw is not
# really a grant, it is a transfer.
#
# `platform_apps` lists what the merchant may name when minting a code. It is deliberately the whole set of
# PlatformApps on the installation rather than a filtered one: every PlatformApp is created by a platform
# operator through Super Admin, so the set is already curated, and inventing a second notion of "approved"
# here would be a list that silently disagrees with the first.
#
# NOTHING SECRET IS RENDERED. A PlatformApp owns an AccessToken through AccessTokenable; only id and name are
# exposed, never the token, and never anything about other accounts the app holds.
class Api::V1::Accounts::Integrations::GrantsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    render json: {
      grants: ::Integrations::AccountGrants.for_account(Current.account),
      platform_apps: PlatformApp.order(:name).map { |app| { id: app.id, name: app.name } }
    }
  end

  def destroy
    app = PlatformApp.find_by(id: params[:id])
    return render json: { error: 'No such integration' }, status: :not_found if app.nil?

    released = ::Integrations::AccountGrants.revoke(account: Current.account, platform_app: app, actor: Current.user)

    render json: { revoked: released.any? || !::Integrations::AccountGrants.granted?(Current.account, app) }
  end
end
