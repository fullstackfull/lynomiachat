# PUT /platform/api/v1/accounts/:account_id/commerce_installation
#
# A partner connecting its own store to one of its merchants' workspaces, server to server, with
# no merchant pasting a token into a form. See Commerce::PartnerInstallation for what is proved
# before anything is written, and docs/commerce/36-partner-commerce-installation.md for the
# contract the other repository is written against.
#
# AUTHORIZATION IS DECLARED, NOT INHERITED -- the same trap as integration_health and
# installation_lifecycle, and worth restating because this is the endpoint where getting it wrong
# would be worst. PlatformController applies `set_resource` and `validate_platform_app_permissible`
# with `only: [:update, :show, :destroy]`, so an action named `create` -- which is what a POST to a
# singular resource routes to by default -- would inherit NEITHER, and this endpoint would attach
# stores into any account id in the URL for any valid token. The action is therefore `update`,
# which is in that list, AND both filters are restated so neither a rename nor an edit to the base
# can remove the check.
#
# PUT, BECAUSE THE REQUEST NAMES AN END STATE. The partner says "this store, with this credential,
# installed in this account" and repeating it changes nothing. There is no id for the caller to
# hold and nothing to keep in step.
#
# VALIDATED AT THE BOUNDARY. A missing parameter, an unknown provider, a malformed credential or an
# unusable store URL is a 422 from here, named -- not an exception out of a service and not a row
# written from input nobody checked.
class Platform::Api::V1::CommerceInstallationsController < PlatformController
  before_action :set_resource
  before_action :validate_platform_app_permissible

  # The statuses the partner's own vocabulary maps onto. `installation_claimed_elsewhere` is a
  # conflict -- the request was well formed and may well succeed once the other account releases
  # the store -- while everything else will be the same answer next time and is classed permanent
  # by the partner's client.
  STATUSES = { 'installation_claimed_elsewhere' => :conflict }.freeze

  # Commerce::Error codes that are a RACE rather than a mistake, and so must not be classed
  # permanent by the caller. STORE_UNAVAILABLE is Commerce::StoreLock saying another operation
  # holds this store right now; the same request a second later is the right thing to do, and a
  # 422 would tell the partner's client to retire it instead.
  RETRYABLE = %w[STORE_UNAVAILABLE RATE_LIMITED TIMEOUT].freeze

  def update
    render json: installation.apply(
      provider: params.require(:provider),
      external_store_id: params.require(:external_store_id),
      base_url: params.require(:base_url),
      credentials: credentials,
      name: params[:name]
    )
  rescue ActionController::ParameterMissing => e
    unprocessable("#{e.param} is required", 'invalid_request')
  rescue Commerce::PartnerInstallation::Refused => e
    render json: { error: e.message, error_code: e.code }, status: STATUSES.fetch(e.code, :unprocessable_entity)
  rescue Commerce::Error => e
    # Commerce::Error is already the shape every other commerce surface answers in: a code and,
    # for a store URL, a safe reason. Provider response bodies and credentials never reach it.
    render json: { error: e.as_json, error_code: e.code.downcase },
           status: RETRYABLE.include?(e.code) ? :conflict : :unprocessable_entity
  end

  private

  def installation
    Commerce::PartnerInstallation.new(account: @resource, platform_app: @platform_app)
  end

  # THE CREDENTIAL'S SHAPE IS CHECKED HERE, against the provider's own declaration of it, so a
  # value that can never work is a 422 naming the field rather than a failed health check against
  # the partner -- and so this endpoint and the merchant-facing form cannot drift into accepting
  # different things.
  def credentials
    formats = Commerce::PartnerInstallation.credential_format(params.require(:provider))
    raise ActionController::ParameterMissing, :provider if formats.nil?

    formats.to_h do |key, format|
      value = params[key].to_s.strip
      raise ActionController::ParameterMissing, key unless value.match?(format)

      [key.to_s, value]
    end
  end

  def unprocessable(error, code)
    render json: { error: error, error_code: code }, status: :unprocessable_entity
  end

  def set_resource
    @resource = Account.find_by(id: params[:account_id])
    return if @resource

    # The same answer as a non-permissible account, deliberately: whether an account id exists on
    # this installation is not something an unauthorized caller gets to learn by asking.
    render json: { error: 'Non permissible resource', error_code: 'non_permissible_resource' },
           status: :unauthorized
  end
end
