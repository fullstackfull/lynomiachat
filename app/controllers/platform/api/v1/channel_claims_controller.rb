# One channel identity, one holder -- claimed and released by the integration that owns the rule.
#
#   GET    /platform/api/v1/channel_claims   what this integration holds
#   POST   /platform/api/v1/channel_claims   claim an identity for one of its accounts
#   DELETE /platform/api/v1/channel_claims   give one back
#
# WHY THE RULE LIVES HERE RATHER THAN IN THE INTEGRATION'S OWN DATABASE. Inboxes are created in
# Lynomia, through nine different paths -- the agent API, five OAuth callbacks, two WhatsApp
# services and the widget onboarding service. A registry kept only on the integration's side
# would be consulted by none of them: a merchant with an administrator identity could connect a
# number in Lynomia directly and the external registry would never hear about it. The claim has
# to be where the creation is.
#
# SCOPED TO THE CALLING APP IN EVERY DIRECTION. A claim belongs to the platform app that made it,
# the uniqueness index is keyed on it, and listing returns only its own. Two integrations on one
# installation do not see or block each other, and an account no integration holds is subject to
# none of this -- which is every account that did not come from one.
class Platform::Api::V1::ChannelClaimsController < PlatformController
  # PlatformController runs set_resource and validate_platform_app_permissible for :destroy,
  # because every other platform resource addresses a row by id. A claim does not: it is
  # addressed by WHAT IT IS -- provider plus identity -- so there is no :id to resolve and the
  # inherited chain would raise before the action ran. The authorization those two callbacks
  # provide is not skipped, only relocated: release! is scoped to @platform_app, so this app can
  # only ever release its own claim, and the spec proves another app's claim survives.
  skip_before_action :set_resource, only: [:destroy]
  skip_before_action :validate_platform_app_permissible, only: [:destroy]

  def index
    claims = ::Channels::Exclusivity.held_by(@platform_app, external_owner_ref: params[:external_owner_ref].presence)

    render json: { claims: claims.map { |claim| present(claim) } }
  end

  def create
    account = permissible_account
    return render_invalid('Not permissible for that account', :unauthorized) if account.nil?

    provider, identity = normalized_identity
    return render_invalid('provider and identity are required') if identity.nil?

    claim = ::Channels::Exclusivity.claim!(
      platform_app: @platform_app, account: account, provider: provider, identity: identity,
      external_owner_ref: params[:external_owner_ref].presence
    )

    render json: present(claim), status: :created
  rescue ::Channels::Exclusivity::Conflict => e
    # Named rather than generic: the merchant who connected this number to their other store is
    # the one who needs to know which store has it, and they cannot find that out from a 409.
    render json: { error: e.message, error_code: 'channel_claimed_elsewhere',
                   held_by: e.claim.external_owner_ref },
           status: :conflict
  end

  def destroy
    provider, identity = normalized_identity
    return render_invalid('provider and identity are required') if identity.nil?

    claim = ::Channels::Exclusivity.release!(platform_app: @platform_app, provider: provider, identity: identity)

    # Releasing something nobody holds is a no-op rather than an error, so a retry after a lost
    # answer succeeds instead of reporting a failure the caller cannot act on.
    render json: { released: claim.present? }
  end

  private

  # NORMALIZED HERE, NOT BY THE CALLER. The whole rule rests on two spellings of one phone number
  # being the same string, so the integration is not trusted to have done it -- it sends what the
  # merchant typed and this decides what it means.
  def normalized_identity
    provider = params[:provider].to_s
    raw = params[:identity].to_s
    return [provider, nil] if provider.blank? || raw.blank?
    return [provider, nil] if ::Channels::Capability::BY_KEY[provider.to_sym].nil?

    [provider, ::Channels::Identity.normalize(provider.to_sym, raw)]
  end

  # A claim may only be made for an account this app already holds. Without this an app could
  # reserve identities against workspaces it was never granted, which is a denial-of-service on
  # another integration's merchants.
  def permissible_account
    account = Account.find_by(id: params[:account_id])
    return nil if account.nil?
    return nil unless @platform_app.platform_app_permissibles.exists?(permissible: account)

    account
  end

  def present(claim)
    {
      id: claim.id, provider: claim.provider, identity: claim.identity,
      account_id: claim.account_id, external_owner_ref: claim.external_owner_ref,
      state: claim.state, claimed_at: claim.created_at
    }
  end

  def render_invalid(message, status = :unprocessable_entity)
    render json: { error: message }, status: status
  end
end
