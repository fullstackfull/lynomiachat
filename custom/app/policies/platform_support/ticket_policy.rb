# Who, inside a customer's account, may see and work a Platform Support ticket
# (docs/platform-support/12-refresh-against-product-refinement.md §3 "Tenant side").
#
#   administrator        every ticket whose subject account is theirs
#   agent                only the tickets they personally reported
#   custom-role holder   EXACTLY the same as an agent
#
# THERE IS NO `CustomRole::PERMISSIONS` ENTRY FOR THIS MODULE, and none is added in V1. That is the approved
# decision, not an omission: a custom role is an account's own way of delegating work inside its own workspace,
# and a complaint raised with the vendor is not work an account delegates. A permission string would also be a
# promise that this policy would then have to keep for every future reader, where today the rule is two lines
# and provably closed. The custom-role holder therefore falls through to the agent branch, which is why the
# `case` below reads the built-in role and nothing else.
#
# SCOPING LIVES HERE, NOT IN THE CALLER. `#resolve` applies `where(account_id:)` ITSELF and callers hand it the
# unscoped relation. This is deliberately unlike Support::TicketPolicy::Scope, which carries no account
# predicate and depends on each of its two callers remembering to supply one -- safe while there are two, and
# not a bet a cross-account table can take.
#
# 404, NEVER 403. Every member record is fetched THROUGH this scope, so a ticket the caller may not see raises
# ActiveRecord::RecordNotFound and the existence of another account's ticket is never confirmed. A `raise`
# would be worse than useless here: Pundit::NotAuthorizedError renders 401 on this surface, which tells a
# prober that the id resolved to something.
class PlatformSupport::TicketPolicy < ApplicationPolicy
  def index? = true
  def create? = true

  # Inherited #show? asks the Scope, so one definition of visibility serves the list, the record and every
  # nested route.
  def update? = show?

  # A ticket is closed, never deleted, and there is no endpoint that could call this.
  def destroy? = false

  class Scope < ApplicationPolicy::Scope
    def resolve
      # Fail closed, in one place: no account, no membership or no authenticated user resolves to nothing. The
      # alternative -- an unscoped relation for an unexpected context -- is the one mistake this table cannot
      # survive.
      return scope.none if account.nil? || account_user.nil? || user.nil?

      base = scope.where(account_id: account.id)

      case account_user.role
      when 'administrator' then base
      when 'agent' then base.where(reporter_id: user.id)
      # A role this policy does not recognise sees nothing, so adding a role to AccountUser cannot silently
      # widen what a Platform Support ticket discloses.
      else scope.none
      end
    end
  end
end
