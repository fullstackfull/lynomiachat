# Lynomia Campaigns (P5D): stopping a campaign.
#
# PREPENDED RATHER THAN EDITED INTO THE OSS CONTROLLER, like every other Lynomia addition to
# an upstream surface: `cancel` is ours, the rest of the controller is upstream's, and keeping
# them apart is what makes the next merge from upstream a merge rather than a conflict.
#
# IT CANNOT BE A DELETE, and that distinction is the point. Destroying a campaign removes its
# recipient snapshot -- the record of who was reached before it was stopped -- which is
# exactly what an operator cancelling a half-sent campaign needs to read afterwards. So the
# campaign and its results are kept and the status says what happened.
#
# AUTHORIZATION IS THE CAMPAIGN'S OWN. Stopping a campaign is a smaller act than deleting one
# and a larger one than reading it; it is gated as an update, because that is what it is -- a
# change to the campaign an administrator may make.
module Custom::Api::V1::Accounts::CampaignsController
  def self.prepended(base)
    base.before_action :resolve_commerce_store, only: [:create]
  end

  def cancel
    # A CAMPAIGN THAT IS NOT THIS ACCOUNT'S IS NOT FOUND, and it is answered here because this
    # is the only action that authorizes the RECORD. `campaign` resolves through
    # `Current.account.campaigns.find_by`, so another account's id yields nil, and
    # `authorize nil, :update?` raises Pundit::NotDefinedError looking for a NilClassPolicy --
    # a 500 for what is an ordinary wrong id. 404 is also the honest answer: within this
    # account, that campaign does not exist.
    return render_not_found_error(I18n.t('errors.campaigns.not_found')) if @campaign.nil?

    authorize @campaign, :update?

    return render_could_not_create_error(I18n.t('errors.campaigns.cannot_cancel')) unless @campaign.cancel!(cancel_reason)

    render :show
  end

  private

  # A short note an operator can leave: "wrong audience", "price was wrong". Bounded because
  # it shares `blocked_reason`, which is a string column, and truncated rather than refused --
  # a cancellation must not fail because somebody typed an essay into the reason box.
  def cancel_reason = params[:reason].to_s.presence&.first(255)

  # THE INSTALLATION A CAMPAIGN BELONGS TO, which upstream has no concept of and therefore
  # does not permit.
  #
  # Without it `commerce_store_id` was never set on a saved campaign, and three things that
  # read it all silently did nothing: the audience's Commerce aggregates were never narrowed
  # to this installation's links, the send boundary never consulted the partner consent
  # store (`return native unless campaign.commerce_store`), and the preview -- which DOES
  # take a store id -- answered a different question from the send. A merchant was shown
  # "40 of your customers" and the campaign then resolved against all 180.
  #
  # ON CREATE ONLY. Which installation a campaign belongs to decides whose consent
  # authorises it, so it is fixed when the campaign is made; letting it move afterwards
  # would change the consent basis of a run that may already have sent.
  #
  # RESOLVED THROUGH THE ACCOUNT'S OWN STORES, never taken on trust, and refused with a 422
  # rather than silently dropped -- the same rule and the same reason as the preview
  # controller: a campaign quietly sent account-wide when a merchant asked for one store is
  # worse than being told the id was wrong.
  def resolve_commerce_store
    requested = params.dig(:campaign, :commerce_store_id).presence
    return if requested.nil?

    @commerce_store_id = Current.account.commerce_stores.where(id: requested).pick(:id)
    render_could_not_create_error(I18n.t('errors.campaigns.store_not_in_account')) if @commerce_store_id.nil?
  end

  def campaign_params
    return super if @commerce_store_id.nil?

    super.merge(commerce_store_id: @commerce_store_id)
  end
end
