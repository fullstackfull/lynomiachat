# Who may see and work a support case (docs/p9/01-architecture.md §6).
#
# Cases are not conversations, so visibility is not inbox membership. A case can exist with no inbox at all, and
# its title and description may describe a customer the reader has no business seeing. So the rule is ownership,
# not channel:
#
#   administrators                      every case in the account
#   agents with `support_ticket_manage` every case in the account
#   everyone else                       the cases assigned to them, assigned to one of their teams, or that they
#                                       opened themselves
#
# `support_ticket_manage` is the account's way of saying "this agent is a support lead". It is validated against
# CustomRole::PERMISSIONS (custom/app/models/custom_role.rb), so it cannot be granted by a typo.
class Support::TicketPolicy < ApplicationPolicy
  MANAGE_PERMISSION = 'support_ticket_manage'.freeze

  def index? = true
  def create? = true

  # Inherited #show? asks the Scope, so one definition of visibility serves the list and the record.
  def update? = show?
  def destroy? = false

  def manage_all?
    account_user&.administrator? || account_user&.permissions&.include?(MANAGE_PERMISSION) || false
  end

  class Scope < ApplicationPolicy::Scope
    # For callers outside a Pundit controller -- the contact activity timeline adapter -- so the visibility rule
    # has exactly one definition and cannot drift between the list and the timeline.
    def self.for(user:, account:, scope: Support::Ticket.all)
      context = { user: user, account: account,
                  account_user: AccountUser.find_by(account_id: account.id, user_id: user&.id) }
      new(context, scope.where(account_id: account.id)).resolve
    end

    def resolve
      return scope if manage_all?

      scope.where(assignee_id: user.id)
           .or(scope.where(team_id: visible_team_ids))
           .or(scope.where(created_by_id: user.id))
    end

    private

    def manage_all?
      account_user&.administrator? ||
        account_user&.permissions&.include?(Support::TicketPolicy::MANAGE_PERMISSION) || false
    end

    # Select, not pluck: this becomes a subquery inside the OR rather than a second round trip whose result is
    # then interpolated.
    def visible_team_ids
      user.teams.where(account_id: account&.id).select(:id)
    end
  end
end
