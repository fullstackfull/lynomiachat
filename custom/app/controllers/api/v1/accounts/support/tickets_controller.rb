# Support cases, account scoped (docs/p9/02-support-tickets.md).
#
# Every link the client sends is resolved through Current.account before it is written, so an id from another
# tenant is a 404 here rather than a validation error later -- and the model's own cross-account validation is
# the net under that. `account_id`, `created_by_id`, `reference_number` and every SLA timestamp are never
# accepted from a request: they are set by the services that own them.
class Api::V1::Accounts::Support::TicketsController < Api::V1::Accounts::Support::BaseController
  before_action :fetch_ticket, only: [:show, :update]
  before_action -> { authorize(::Support::Ticket) }, only: [:index, :create]
  before_action -> { authorize(@ticket, :update?) }, only: [:update]
  before_action -> { authorize(@ticket, :show?) }, only: [:show]

  def index
    @tickets = ::Support::Tickets::Query.new(
      account: Current.account, scope: ticket_scope, user: Current.user, params: filter_params
    ).call
    @counts = ::Support::Tickets::Counts.new(scope: ticket_scope, user: Current.user).call
  end

  def show; end

  def create
    @ticket = ::Support::Tickets::Create.new(
      account: Current.account, user: Current.user, attributes: resolved_attributes(create_params)
    ).perform
    render :show, status: :created
  end

  def update
    @ticket = ::Support::Tickets::Update.new(
      ticket: @ticket, user: Current.user, attributes: resolved_attributes(update_params)
    ).perform
    render :show
  end

  private

  # Found through the policy scope, so a case the caller may not see is a 404 and not a 403 that confirms it
  # exists. Accepts a reference as well as an id, because an operator pastes `TCK-000123` from an email.
  def fetch_ticket
    @ticket = if params[:id].to_s.match?(/\A\d+\z/)
                ticket_scope.find(params[:id])
              else
                ticket_scope.find_by!(reference_number: ::Support::Ticket.reference_number_from(params[:id]))
              end
  end

  def filter_params
    params.permit(:status, :priority, :category, :assignee_id, :team_id, :contact_id, :inbox_id, :conversation_id,
                  :sla, :q, :since, :until, :sort, :page, :per_page,
                  status: [], priority: [], category: []).to_h.symbolize_keys
  end

  # A new case always opens. Letting a client create one already `resolved` would skip the lifecycle and leave a
  # case with a resolution it never had.
  def create_params
    params.require(:ticket).permit(:title, :description, :category, :priority, :conversation_id, :contact_id,
                                   :inbox_id, :assignee_id, :team_id, :sla_policy_id, label_list: [])
  end

  def update_params
    params.require(:ticket).permit(:title, :description, :category, :priority, :status, :conversation_id,
                                   :contact_id, :inbox_id, :assignee_id, :team_id, :sla_policy_id, label_list: [])
  end

  # Ids in, records out, every one of them through Current.account. This is the single enforcement point for
  # cross-tenant linking; ActiveRecord::RecordNotFound renders as 404 through the inherited handler.
  LINKS = {
    'conversation_id' => [:conversation, :conversations],
    'contact_id' => [:contact, :contacts],
    'inbox_id' => [:inbox, :inboxes],
    'assignee_id' => [:assignee, :users],
    'team_id' => [:team, :teams],
    'sla_policy_id' => [:sla_policy, :sla_policies]
  }.freeze

  def resolved_attributes(permitted)
    attributes = permitted.to_h
    LINKS.each do |key, (association, collection)|
      next unless attributes.key?(key)

      value = attributes.delete(key)
      attributes[association.to_s] = value.presence && Current.account.public_send(collection).find(value)
    end
    attributes
  end
end
