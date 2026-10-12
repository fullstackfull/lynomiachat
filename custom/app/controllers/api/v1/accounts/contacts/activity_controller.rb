# One contact's activity timeline (docs/p8/03-contact-activity-timeline.md).
#
# Authorization follows the CONTACT, not the report permission: an agent who may open a contact should see what
# happened with that contact. Analytics is account-wide reporting and is administrator-only; this is one record's
# own history, so it follows that record's policy, exactly as the contact's attachment and conversation lists do.
#
# Within that, what the caller sees is still narrowed to the conversations they may open, by the same
# Conversations::PermissionFilterService the attachment list uses.
class Api::V1::Accounts::Contacts::ActivityController < Api::V1::Accounts::Contacts::BaseController
  rescue_from CustomExceptions::Timeline::Base, with: :render_timeline_error

  def index
    authorize @contact, :show?

    render json: Contacts::ActivityTimelineQuery.new(
      account: Current.account,
      contact: @contact,
      user: Current.user,
      categories: params[:categories],
      page: { cursor: params[:cursor], limit: params[:limit] }
    ).call
  end

  private

  def render_timeline_error(exception)
    Rails.logger.info("Contact timeline request rejected: #{exception.class.name}")
    render json: exception.to_hash, status: exception.http_status
  end
end
