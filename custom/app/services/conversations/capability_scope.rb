# DECISION 1. The ONE definition of what the three `conversation_*` capabilities mean, and the only place that
# decides it.
#
# WHY IT IS ONE OBJECT. Before this, the rule had four independent expressions and none of them was
# authoritative: `Conversations::PermissionFilterService` (inbox membership, no capability read at all),
# `Conversations::UnreadCounts::Counter#permission_mode` (the only server-side reader, and behind a flag that
# ships disabled), `Contacts::ActivityTimelineQuery#visible_inbox_ids` (a hand-copy of the filter service's rule),
# and `applyRoleFilter` in the browser, which implemented exactly the semantics the names promise and was the
# only thing narrowing anything. Adding a fifth expression in a policy would have made the drift worse rather
# than better. This is the Pundit-Scope pattern the product already uses for support cases
# (custom/app/policies/support/ticket_policy.rb), generalised one step because three different kinds of caller
# need the same answer: a relation, a record, and a mode name.
#
# THE SEMANTICS, which are the ones the product has displayed all along:
#
#   conversation_manage                 every conversation the holder could already reach
#   conversation_unassigned_manage      the unassigned ones, plus their own
#   conversation_participating_manage   their own
#   none of the three                   none -- but see the grandfather rule below
#
# WIDEST WINS when a set names more than one. That is what the browser does
# (app/javascript/dashboard/store/modules/conversations/helpers.js:85-106) and what the unread counter does
# (counter.rb:157-168), so it is the behaviour an administrator has been shown.
#
# THE CEILING IS NOT TOUCHED. This NARROWS; it never widens. Whatever a caller was already limited to --
# inbox membership in the filter service, inbox-or-team in the record policy, the account in search -- still
# applies, and this is intersected with it. In particular the existing inbox/team asymmetry (a team member with
# no inbox membership can open a conversation the list would not return, asserted at
# spec/policies/conversation_policy_spec.rb) is left exactly as it is: changing it is not part of this decision.
#
# THE GRANDFATHER RULE. `custom_roles.conversation_scope_enforced` is false only for sets that existed before
# this release AND name none of the three (custom/db/migrate/20261011180000). Those sets' holders keep the
# access they have, because the capability was not enforcing when their administrator chose it. Every new set,
# and every existing set whose conversation capabilities an operator edits, is enforced -- so absence is never
# read as unrestricted access for anything configured from now on.
#
# `:none` IS A REAL ANSWER, not a bug to route around. A set that is enforced and names none of the three means
# no conversation access, and the caller gets an empty relation or a refusal.
class Conversations::CapabilityScope
  MANAGE_ALL = 'conversation_manage'.freeze
  UNASSIGNED = 'conversation_unassigned_manage'.freeze
  PARTICIPATING = 'conversation_participating_manage'.freeze
  CAPABILITIES = [MANAGE_ALL, UNASSIGNED, PARTICIPATING].freeze

  # The counter's vocabulary, kept so that it can delegate to this object without its Redis key families moving.
  MODES = %i[base unassigned_and_mine mine none].freeze

  # Unassigned means what the rest of the product means by it: no human assignee AND no bot assignee
  # (app/models/conversation.rb:89). A bot-assigned conversation is not unassigned, which matters because the
  # unread counter already excludes it and the two must agree.
  UNASSIGNED_OR_MINE_SQL = '(conversations.assignee_id = :user_id OR ' \
                           '(conversations.assignee_id IS NULL AND conversations.assignee_agent_bot_id IS NULL))'.freeze

  def self.for(account_user)
    new(account_user)
  end

  def initialize(account_user)
    @account_user = account_user
  end

  # :base, :unassigned_and_mine, :mine or :none.
  def mode
    @mode ||= resolve_mode
  end

  def unrestricted?
    mode == :base
  end

  def none?
    mode == :none
  end

  # The relation, narrowed. Never widened: every branch either returns the relation it was given or a subset of
  # it.
  def narrow(relation, user:)
    case mode
    when :base then relation
    when :unassigned_and_mine then relation.where(UNASSIGNED_OR_MINE_SQL, user_id: user.id)
    when :mine then relation.where(assignee_id: user.id)
    else relation.none
    end
  end

  # The same question about one record, so the list and the record cannot disagree. Reads the loaded attributes
  # rather than issuing a query, because this is called per record on the show path.
  def permits?(conversation, user:)
    case mode
    when :base then true
    when :unassigned_and_mine then mine?(conversation, user) || unassigned?(conversation)
    when :mine then mine?(conversation, user)
    else false
    end
  end

  private

  def mine?(conversation, user)
    conversation.assignee_id.present? && conversation.assignee_id == user.id
  end

  def unassigned?(conversation)
    conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil?
  end

  # A membership with no set attached, or one that is not an agent, is not narrowed by this at all: an
  # administrator's reach is decided by the `role` column everywhere in this product, never by a capability
  # list (custom/app/models/custom/account_user.rb:23-25).
  def resolve_mode
    return :base unless custom_role_agent?

    return :base if permissions.include?(MANAGE_ALL)
    return :unassigned_and_mine if permissions.include?(UNASSIGNED)
    return :mine if permissions.include?(PARTICIPATING)

    enforced? ? :none : :base
  end

  # Keyed off the MARKER in the capability list rather than off `custom_role_id`, and that is deliberate: the
  # marker is appended by `Custom::AccountUser#permissions`, which is where DECISION 2 applies the entitlement
  # upper bound. An account that has lost the `custom_roles` entitlement therefore arrives here with its
  # built-in agent list and no marker, so its members are treated as plain agents -- the least-privileged
  # compatible behaviour -- instead of being denied every conversation by a capability they are no longer
  # entitled to hold. Reading `custom_role_id` would have bypassed that.
  def custom_role_agent?
    @account_user&.agent? && permissions.include?(Custom::AccountUser::CUSTOM_ROLE_MARKER)
  end

  # Read from the membership's own permission list, which is where Decision 2 applies the entitlement upper
  # bound -- so a set whose account has lost the `custom_roles` entitlement arrives here as a plain agent and is
  # not narrowed by a capability it is no longer entitled to hold.
  def permissions
    @permissions ||= Array(@account_user.permissions)
  end

  def enforced? = @account_user.custom_role&.conversation_scope_enforced != false
end
