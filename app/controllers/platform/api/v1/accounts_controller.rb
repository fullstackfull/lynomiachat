class Platform::Api::V1::AccountsController < PlatformController
  def index
    @resources = @platform_app.platform_app_permissibles
                              .where(permissible_type: 'Account')
                              .includes(:permissible)
                              .map(&:permissible)
  end

  def show; end

  def create
    @resource = Account.create!(account_params)
    update_resource_features
    @platform_app.platform_app_permissibles.find_or_create_by(permissible: @resource)
  end

  def update
    @resource.update!(account_params)
    update_resource_features
  end

  def destroy
    DeleteObjectJob.perform_later(@resource)
    head :ok
  end

  private

  def set_resource
    @resource = Account.find(params[:id])
  end

  def account_params
    permitted_params.except(:features)
  end

  # Lynomia (docs/p-final/06-clean-code-review.md §3): this used to write the account's feature bitmask
  # directly. For a capability a plan sells, that is a commercial decision with no record of who made it or
  # why, and Billing::FeatureSync reverts it at the next plan change. Billing::OverrideGrant is the one writer
  # of commercial entitlement state, so the write goes through it: a capability a plan can sell becomes an
  # audited override attributed to this app, and anything else keeps the direct write it always had.
  #
  # The account is already saved when this runs (create! / update! above), because the grant writes the flags
  # itself and must not do so on an unsaved record.
  def update_resource_features
    return if permitted_params[:features].blank?

    ::Billing::OverrideGrant.new(@resource, actor: @platform_app)
                            .write_features!(permitted_params[:features], reason: feature_write_reason)
  end

  def feature_write_reason
    "Set through the Platform API by #{@platform_app.name.presence || "app ##{@platform_app.id}"}"
  end

  def permitted_params
    params.permit(:name, :locale, :domain, :support_email, :status, features: {}, limits: {}, custom_attributes: {})
  end
end
