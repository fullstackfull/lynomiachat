# Shared boundary for every support-case endpoint (docs/p9/01-architecture.md §12).
#
# Three things every action needs, in one place so no action can be written without them: the account feature
# gate, the Pundit authorization, and the 422 rendering for a refused request. Account scoping itself comes from
# Api::V1::Accounts::BaseController, which sets Current.account; `params[:account_id]` is never read here.
class Api::V1::Accounts::Support::BaseController < Api::V1::Accounts::BaseController
  FEATURE = 'lynomia_support_tickets'.freeze

  before_action :ensure_support_enabled
  rescue_from CustomExceptions::Tickets::Base, with: :render_ticket_error

  private

  # A disabled feature is 404, not 403: the account has no support module, so the endpoint does not exist for it.
  # This matches how the product treats every other account feature and avoids telling a caller what it could
  # have if it paid.
  def ensure_support_enabled
    return if Current.account.feature_enabled?(FEATURE)

    render json: { error: I18n.t('errors.tickets.feature_disabled') }, status: :not_found
  end

  def render_ticket_error(exception)
    Rails.logger.info("Support ticket request rejected: #{exception.class.name}")
    render json: exception.to_hash, status: exception.http_status
  end

  def ticket_scope
    policy_scope(::Support::Ticket.where(account_id: Current.account.id))
  end
end
