class Platform::Api::V1::AccountsController < PlatformController
  # Optionally narrowed by custom attributes: ?custom_attributes[store_syria_store_id]=42
  #
  # WHY A FILTER AND NOT JUST A CLIENT-SIDE SCAN. An external platform recovers from a create whose answer was
  # lost by asking "does the account I may have just made already exist?". Without a filter that question costs
  # the app's entire account list on every recovery -- for an installation with thousands of linked stores,
  # megabytes to find one row. The predicate is applied on top of the permissible scope, never instead of it,
  # so it can only ever narrow what the app could already read and cannot be used to discover anything.
  def index
    scope = @platform_app.platform_app_permissibles
                         .where(permissible_type: 'Account')
                         .includes(:permissible)

    # filter_map, because a grant can outlive what it points at. Nothing destroys
    # platform_app_permissibles when an Account is deleted -- Account has no association for them, and
    # DELETE /platform/api/v1/accounts/:id only enqueues DeleteObjectJob -- so the row survives pointing at a
    # dead id and `permissible` resolves to nil. Before this, those nils went straight into the view; with a
    # filter reading custom_attributes off each one they would be a 500 on the recovery path that exists
    # precisely to clean such things up.
    @resources = scope.filter_map(&:permissible)
    @resources = filter_by_custom_attributes(@resources)
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

  # Filtered in Ruby rather than in SQL. The set is already bounded by this app's permissibles and is loaded
  # either way to be rendered, so a jsonb containment predicate would buy nothing here while adding a
  # database-specific query to a controller that has none. Values are compared as strings because the query
  # string has no types -- `?custom_attributes[store_syria_store_id]=42` arrives as "42" whether the stored
  # value is the number 42 or the string.
  def filter_by_custom_attributes(accounts)
    filter = params[:custom_attributes]
    return accounts if filter.blank?

    filter = filter.permit!.to_h if filter.respond_to?(:permit!)
    return accounts unless filter.is_a?(Hash)

    accounts.select do |account|
      attributes = account.custom_attributes || {}
      filter.all? { |key, value| attributes[key.to_s].to_s == value.to_s }
    end
  end

  def permitted_params
    params.permit(:name, :locale, :domain, :support_email, :status, features: {}, limits: {}, custom_attributes: {})
  end
end
