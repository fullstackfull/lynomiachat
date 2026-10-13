# The Lynomia Platform Support Desk, operator side — the READS
# (docs/platform-support/12-refresh-against-product-refinement.md §2, §3,
# docs/platform-support/05-super-admin-operations.md).
#
# Server-rendered ERB inside the existing Super Admin shell, NOT Administrate: the arrangement the Operations
# Center already proves here — a route drawer, a controller inheriting SuperAdmin::ApplicationController, and
# Tailwind ERB with no Vue island, because nothing on these pages needs client state a form and a link cannot
# express.
#
# TWO LAYERS, NOT ONE.
# Authentication is `authenticate_super_admin!`, applied by the parent to every action; there is no Pundit on
# this surface and this controller does not invent one. On top of it sits the one layer Operations does not
# have: `require_support_agent!` resolves the acting `PlatformSupport::Agent` for `current_super_admin` and
# refuses when there is none or it is inactive. Being a Super Admin is not being support staff, and the
# brief's future dedicated support role needs that separation to exist from day one. No agent rows are seeded,
# so a fresh installation refuses this desk until an operator creates one — the fail-closed state, by design.
#
# THIS CLASS HOLDS ONLY THE READS. The six operator decisions live in
# `SuperAdmin::PlatformSupportActionsController`, which inherits from this one and therefore inherits the
# guard rather than restating it. The split is along the line that matters on this surface: everything here is
# a GET, everything there is a POST or a PATCH, so no operator decision can be triggered by a link somebody
# pastes into a chat.
#
# Lookups are deliberately NOT account-scoped: this surface is installation-wide and an operator works across
# accounts. The boundary that matters is the two before_actions. The lookup itself is `find_by` plus a redirect
# with an alert, never `find!` — the Operations mutation pattern.
class SuperAdmin::PlatformSupportController < SuperAdmin::ApplicationController
  include ActiveStorage::Streaming

  PER_PAGE = 25

  # The two ActiveStorage attachment names this module owns, and the two records that can carry them. An id
  # outside both lists is not a Platform Support attachment and 404s, so this route cannot be turned into a
  # reader for another subsystem's blobs.
  ATTACHMENT_NAMES = %w[platform_support_message_files platform_support_note_files].freeze
  ATTACHMENT_PARENT_TYPES = %w[PlatformSupport::Message PlatformSupport::InternalNote].freeze

  before_action :require_support_agent!

  # The queue: filters, Kaminari pagination, and the contract's default order.
  def show
    @tickets = queue_scope.page(params[:page]).per(PER_PAGE)
    @assignees = PlatformSupport::Agent.where(active: true).order(:display_name)
  end

  # One ticket, in full: the public thread, the internal notes, the events, and the account's own context.
  def ticket
    return if load_ticket.nil?

    @messages = @ticket.messages.order(:created_at)
    @notes = @ticket.internal_notes.order(:created_at)
    @events = @ticket.events.order(:created_at)
    @assignees = PlatformSupport::Agent.where(active: true).order(:display_name)
    @subscription = @ticket.account&.billing_subscription
  end

  # The staff half of the first authorized ActiveStorage download in this repository.
  #
  # A blob on this surface is reached only through here: never a `rails_blob_path`, never a signed id rendered
  # into a page. Blob URLs do not expire in this installation, so a leaked signed id would be a permanent one.
  # The acting agent is already resolved by the before_action; what this action checks is that the id names an
  # attachment of a record this module owns.
  def attachment
    record = ActiveStorage::Attachment.find_by(id: params[:id], name: ATTACHMENT_NAMES,
                                               record_type: ATTACHMENT_PARENT_TYPES)
    return head(:not_found) if record.nil?

    inline = ActiveStorage.content_types_allowed_inline.include?(record.blob.content_type)
    send_blob_stream(record.blob, disposition: inline ? 'inline' : 'attachment')
  end

  private

  # Staff authority is a row, not a role name, and the rule that reads that row lives in
  # `PlatformSupport::StaffAuthorizer` -- which is also what decides who may reassign, so there is one answer
  # to "is this person staff" rather than one per controller.
  def require_support_agent!
    @agent = PlatformSupport::StaffAuthorizer.agent_for(current_super_admin)
    return if @agent.present?

    redirect_to super_admin_root_path,
                alert: t('super_admin.platform_support.not_an_agent',
                         default: 'You are not an active Lynomia support agent, so the support desk is not open to you.')
  end

  def load_ticket
    @ticket = PlatformSupport::Ticket.find_by(id: params[:id])
    if @ticket.nil?
      redirect_to super_admin_platform_support_path,
                  alert: t('super_admin.platform_support.ticket_not_found', default: 'That ticket no longer exists.')
    end
    @ticket
  end

  # `includes(:account, :assignee)`, and the queue's plan column reads the ticket's OWN
  # `plan_name_at_creation` snapshot rather than joining through billing_subscriptions per row: the account and
  # plan columns are exactly where the N+1 this surface has already measured would reappear
  # (docs/platform-support/05-super-admin-operations.md §2).
  #
  # A filter value outside its allow-list is DROPPED rather than queried, so a hand-edited query string cannot
  # produce an empty queue that looks like a real answer.
  #
  # Order is the contract's: status, then priority worst first, then the stalest activity last.
  def queue_scope
    filters = {
      status: params[:status].presence_in(PlatformSupport::Ticket.statuses.keys),
      priority: params[:priority].presence_in(PlatformSupport::Ticket.priorities.keys),
      category: params[:category].presence_in(PlatformSupport::Ticket::CATEGORIES),
      account_id: params[:account_id].presence
    }.compact

    scope = PlatformSupport::Ticket.includes(:account, :assignee).where(filters)
    apply_search(apply_assignee_filter(scope)).order(:status, priority: :desc, last_activity_at: :desc)
  end

  # `unassigned` is a literal, because a NULL cannot be expressed in a query string.
  def apply_assignee_filter(scope)
    return scope if params[:assignee_id].blank?
    return scope.where(assignee_id: nil) if params[:assignee_id] == 'unassigned'

    scope.where(assignee_id: params[:assignee_id])
  end

  # Reference, subject or account name in one box. The reference matches `LYN-000123` and `123` alike, for the
  # reason the tenant desk already records: an operator pasting a reference out of an email should not have to
  # strip it.
  def apply_search(scope)
    term = params[:q]
    return scope if term.blank?

    scope.left_joins(:account).where(
      'platform_support_tickets.subject ILIKE :like OR accounts.name ILIKE :like ' \
      'OR platform_support_tickets.reference_number = :reference',
      like: "%#{term}%", reference: term[/\d+/].to_i
    )
  end
end
