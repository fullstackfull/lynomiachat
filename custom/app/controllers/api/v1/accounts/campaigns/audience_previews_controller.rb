# Lynomia Campaigns (docs/campaigns/05-preview-and-dedup.md): how many contacts a one-off campaign's recipients select
# now, each contact once across its labels and shared audiences, counted on the server. The campaign resolves them again
# when it is sent, so this is a count, never a list. Whoever may create campaigns may preview (CampaignPolicy).
#
#   POST /campaigns/audience_preview   audience: [{ type: 'Label' | 'Audience', id }]   →   { count }
class Api::V1::Accounts::Campaigns::AudiencePreviewsController < Api::V1::Accounts::BaseController
  def create
    authorize Campaign, :create?
    campaign = Current.account.campaigns.new(campaign_type: :one_off, audience: params.permit(audience: [:type, :id]).require(:audience))
    return render_could_not_create_error(I18n.t('errors.campaigns.audience_not_shared')) unless campaign.audiences_shared_in_account?

    render json: { count: campaign.audience_contacts.count }
  end
end
