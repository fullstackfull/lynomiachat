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
  def cancel
    authorize @campaign, :update?

    return render_could_not_create_error(I18n.t('errors.campaigns.cannot_cancel')) unless @campaign.cancel!(cancel_reason)

    render :show
  end

  private

  # A short note an operator can leave: "wrong audience", "price was wrong". Bounded because
  # it shares `blocked_reason`, which is a string column, and truncated rather than refused --
  # a cancellation must not fail because somebody typed an essay into the reason box.
  def cancel_reason = params[:reason].to_s.presence&.first(255)
end
