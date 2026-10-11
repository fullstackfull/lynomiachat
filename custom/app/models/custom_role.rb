# A named set of capabilities an account defines and attaches to one of its members
# (docs/p-final/clean-room/specs/C-account-role-permissions.md).
#
# Chatwoot gives a membership one of two roles, agent or administrator, and Lynomia has capabilities that fit
# neither: acting on a store order is a commercial action with money attached, and seeing every support case in
# the account is what a support lead does. Handing out account administration to get either would be worse than
# the problem.
#
# The capability list is a plain array on the row, which the `permissions` text[] column already expresses. No
# join table, no capability registry, no permission object: the published vocabulary plus validation is all that
# any caller needs (package C §9).
#
# PERMISSIONS is the closed vocabulary. It is closed on purpose: a free-text column would let an account invent
# a capability name that some future check happened to honour. It is also the constant
# `spec/factories/custom_roles.rb` and `custom/app/policies/support/ticket_policy.rb` name.
class CustomRole < ApplicationRecord
  # The same identifiers the client publishes in app/javascript/dashboard/constants/permissions.js, in the same
  # order, plus one the client no longer offers.
  PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    contact_manage
    report_manage
    commerce_order_manage
    support_ticket_manage
    knowledge_base_manage
  ].freeze

  # Lynomia publishes its own documentation and a workspace has no knowledge base, so the client stopped
  # offering this one. It stays acceptable here because roles created before that change still carry it, and
  # dropping it from the validation would make those rows unsaveable -- and because global search still consults
  # it to reach a workspace's frozen pages (app/javascript/dashboard/constants/permissions.js:36).
  RETIRED_PERMISSIONS = %w[knowledge_base_manage].freeze

  belongs_to :account

  # Detached, never destroyed. Deleting a role must lose no membership: each affected member simply has no role
  # afterwards and reverts to the capabilities its built-in role gives it (package C §6). There is no foreign
  # key on `account_users.custom_role_id`, so clearing the attachment is this model's job.
  #
  # `dependent: :nullify` would do it in one `update_all` -- and skip every callback on the way. Chatwoot
  # declares `custom_role_id` to be a column that changes which conversations a member can see, and invalidates
  # their cached filtered unread counts whenever it moves (app/models/account_user.rb:85-87,93-95). Through
  # `update_all` that invalidation never runs, so deleting a set would leave its holders counting conversations
  # under the visibility it used to grant -- while the identical change made on the agent endpoint invalidates
  # correctly. One statement per holder keeps the two paths honest, and it puts the capability change on the
  # audit trail, which is where a reader looks for why somebody's access changed.
  has_many :account_users, dependent: nil
  before_destroy :detach_memberships

  # The same reason, one step earlier: three of this vocabulary's capabilities decide how much of the inbox a
  # member's filtered unread counts cover (app/services/conversations/unread_counts/counter.rb:157-168), and
  # those counts are cached in Redis under a version per member. Chatwoot bumps that version when a membership's
  # attachment moves; editing the set's capabilities changes exactly the same thing for everyone holding it, and
  # nothing on the membership row changes, so without this the holders keep counting under the capabilities the
  # set used to grant until the version expires.
  after_update_commit :invalidate_holders_visibility, if: :saved_change_to_permissions?

  validates :name, presence: true
  # The client requires at least one capability before it will submit (CustomRoleModal.vue:48), and a set that
  # grants nothing is a set somebody will later wonder about, so the server says the same thing.
  validates :permissions, presence: true
  validate :permissions_are_published

  private

  # The account-destroy path reaches here with no account left. `dependent: :destroy_async` runs the job only
  # once the owner row is gone -- Rails' own DestroyAssociationAsyncJob raises unless it is -- and a membership
  # whose `account` no longer resolves cannot be saved, because `belongs_to :account` is required
  # (app/models/account_user.rb:30 under `load_defaults 7.0`). So the detach below would raise, the job would
  # fail, and the set's row would survive the account that owned it: there is no foreign key on
  # `custom_roles.account_id` to clean it up.
  #
  # Nothing is lost by returning early. The memberships are being destroyed with the account, and there is no
  # cached visibility left to invalidate for an account that no longer exists.
  def detach_memberships
    return if account.nil?

    account_users.each { |membership| membership.update!(custom_role_id: nil) }
  end

  # One pipelined round trip for every holder, rather than a statement each: the set is edited rarely and may
  # have many holders.
  def invalidate_holders_visibility
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account)
                                                           .users_visibility_changed!(user_ids: account_users.pluck(:user_id))
  end

  # Reported as one error naming every unknown value, so a client sending two typos learns about both.
  def permissions_are_published
    unknown = permissions.to_a.map(&:to_s) - PERMISSIONS
    return if unknown.empty?

    errors.add(:permissions, I18n.t('errors.custom_roles.unknown_permissions', permissions: unknown.sort.join(', ')))
  end
end
