# Minting the proof that a merchant controls this account.
#
#   POST /api/v1/accounts/:account_id/integrations/account_link_code   a one-time code, shown once
#   GET  /api/v1/accounts/:account_id/integrations/account_link_code   progress: none | waiting | expired | claimed | connected | revoked
#
# The merchant pastes the code into the external platform, which redeems it server to server at
# POST /platform/api/v1/account_links. No token and no account identifier ever passes through the merchant's
# hands -- only a string that is worthless without the platform credential on the other side.
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
    render json: ::Integrations::AccountLinkCode.create(account: Current.account, user: Current.user), status: :created
  end
end
