# Lynomia Campaigns (docs/campaigns/05-preview-and-dedup.md): how many contacts a one-off campaign's recipients select
# now, each contact once across its labels and shared audiences, counted on the server. The campaign resolves them again
# when it is sent, so this is a count, never a list. Whoever may create campaigns may preview (CampaignPolicy).
#
#   POST /campaigns/audience_preview
#     audience: [{ type: 'Label' | 'Audience', id }]
#     commerce_store_id: optional -- count as a campaign FOR THAT INSTALLATION would
#   →   { count }
#
# THE STORE SCOPE IS PART OF THE QUESTION, NOT A FILTER ON THE ANSWER. A store-scoped campaign
# reads its audience's Commerce aggregates against that installation's links only, so a
# preview that omitted the store would answer a different question from the one the send
# answers -- "more than three orders anywhere" instead of "more than three orders with us" --
# and the merchant would be shown a number their campaign cannot reach. Previewing and sending
# have to be the same query or the preview is decoration.
class Api::V1::Accounts::Campaigns::AudiencePreviewsController < Api::V1::Accounts::BaseController
  def create
    authorize Campaign, :create?
    campaign = Current.account.campaigns.new(campaign_type: :one_off, commerce_store_id: scoped_store_id,
                                             audience: params.permit(audience: [:type, :id]).require(:audience))
    return render_could_not_create_error(I18n.t('errors.campaigns.audience_not_shared')) unless campaign.audiences_shared_in_account?

    render json: { count: campaign.audience_contacts.count }
  # The filter exceptions are not globally rescued (request_exception_handler.rb handles
  # RecordInvalid and the inbox limit only), so an invalid condition inside a saved audience
  # -- or a store id that is not this account's -- would be a 500 rather than a 422. Rescued
  # the same way Api::V1::Accounts::ContactsController#filter rescues them.
  rescue CustomExceptions::CustomFilter::InvalidAttribute,
         CustomExceptions::CustomFilter::InvalidOperator,
         CustomExceptions::CustomFilter::InvalidQueryOperator,
         CustomExceptions::CustomFilter::InvalidValue => e
    render_could_not_create_error(e.message)
  end

  private

  # Resolved through the ACCOUNT'S OWN stores rather than taken on trust: an id belonging to
  # another tenant is refused here with a 422 rather than silently narrowing the count to
  # zero. An empty preview reads as "nobody qualifies", which is the wrong thing to tell
  # somebody whose real mistake was naming a store that is not theirs.
  def scoped_store_id
    requested = params[:commerce_store_id].presence
    return if requested.nil?

    Current.account.commerce_stores.where(id: requested).pick(:id) ||
      raise(CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: 'commerce_store_id'))
  end
end
