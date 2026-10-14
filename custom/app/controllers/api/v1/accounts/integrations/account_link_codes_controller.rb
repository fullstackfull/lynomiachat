# Minting the proof that a merchant controls this account, for ONE named integration.
#
#   GET  /api/v1/accounts/:account_id/integrations/account_link_code   progress: none | waiting | expired | claimed | connected | revoked
#   POST /api/v1/accounts/:account_id/integrations/account_link_code   a one-time code, shown once
#
# The merchant pastes the code into the external platform, which redeems it server to server at
# POST /platform/api/v1/account_links. No token and no account identifier ever passes through the merchant's
# hands -- only a string that is worthless without the platform credential on the other side, and now also
# worthless to any integration but the one they named.
#
# THE AUDIENCE IS MANDATORY. A code with no audience is a bearer token for whoever presents it first, and on
# an installation carrying more than one app that is reachable by ordinary mistake: paste it into the wrong
# integration's field and that app gets a working grant while the intended one is told "Invalid or expired
# code". `platform_app_id` is required here, and redemption refuses anybody else.
#
# ADMINISTRATOR, NOT MERELY A MEMBER. A code authorizes an external application to sign in to this workspace,
# which is an owner-level decision, so it is gated on the account's administrator ROLE. That is checked through
# `administrator?` on the membership's role column rather than through a permission list, because a custom role
# can carry permissions but cannot reach administrator -- custom/app/models/custom/account_user.rb says so
# explicitly: "every administrator check in the product reads the `role` column through `administrator?`, not
# this list". Reading the permission list here would let an account owner hand out the ability to give an
# outside app access to the whole workspace, which is not a permission this product has ever offered.
class Api::V1::Accounts::Integrations::AccountLinkCodesController < Api::V1::Accounts::BaseController
  # Api::BaseController#check_admin_authorization? -- the product's existing administrator gate, reused rather
  # than restated. A user with no membership on this account never reaches it: the base controller refuses them.
  before_action :check_admin_authorization?

  def show
    render json: ::Integrations::AccountLinkCode.status(Current.account)
  end

  def create
    app = PlatformApp.find_by(id: params[:platform_app_id])

    # A missing or unknown app is refused rather than defaulted. Defaulting is the bearer behaviour this
    # endpoint exists to end, and there is no sensible app to default TO -- the installation may carry several.
    return render json: { error: 'platform_app_id is required' }, status: :unprocessable_entity if app.nil?

    render json: ::Integrations::AccountLinkCode.create(
      account: Current.account, user: Current.user, platform_app: app
    ), status: :created
  end
end
