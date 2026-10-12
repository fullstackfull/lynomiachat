# A member of Lynomia's own support staff (docs/platform-support/12-refresh-against-product-refinement.md §1 M1,
# §3).
#
# BEING A SUPER ADMIN IS NOT BEING SUPPORT STAFF. The Super Admin console is reached by everyone who
# administers this installation; this desk reads every tenant's complaints and writes replies in Lynomia's name.
# So the staff controllers resolve one of these rows for `current_super_admin` and refuse when there is none or
# it is inactive. No row is seeded anywhere -- who the first agents are is an owner decision -- and the desk
# refusing every action until an operator creates one is the correct fail-closed state, not a gap.
#
# WHY THIS IS WHAT `platform_support_tickets.assignee_id` POINTS AT. The tenant helpdesk requires its assignee
# to be an AccountUser of the ticket's account, which would mean adding Lynomia staff to the customer's
# account -- the one thing this product must never do. Here the foreign key makes the right answer structural:
# a tenant user id cannot be written to `assignee_id` at all, so no AccountUser membership is ever created for
# staff.
#
# The `user.is_a?(SuperAdmin)` check runs on create because STI constrains READS, not writes: without it a
# plain tenant user id could be seeded as staff and `PlatformSupport::Agent.find_by(user_id:)` would happily
# return it. When the brief's future dedicated support-agent role arrives, this validation is the one place
# that relaxes.
class PlatformSupport::Agent < ApplicationRecord
  self.table_name = 'platform_support_agents'

  # The only capability distinction in V1: a lead may reassign another agent's ticket and edit SLA policies.
  # Anything finer is a later phase, and a finer vocabulary invented now would be one nobody has used.
  enum :role, { agent: 0, lead: 1 }

  belongs_to :user

  has_many :assigned_tickets, class_name: 'PlatformSupport::Ticket', foreign_key: :assignee_id,
                              dependent: :nullify, inverse_of: :assignee
  # restrict_with_error rather than destroy: an internal note is the record of a decision and must not lose its
  # author. An operator who should no longer work the desk is deactivated, not deleted.
  has_many :internal_notes, class_name: 'PlatformSupport::InternalNote',
                            dependent: :restrict_with_error, inverse_of: :agent

  validates :display_name, presence: true, length: { maximum: 255 }
  validates :user_id, uniqueness: true
  validate :user_must_be_a_super_admin, on: :create

  scope :active, -> { where(active: true) }

  before_validation :snapshot_display_name

  # So the three-way actor-name chain that Custom::AuditLog and the event recorder both use resolves a staff
  # actor to its snapshot rather than falling through to the class name.
  def available_name
    display_name
  end

  private

  # Refreshed on every save, not only on create: the snapshot exists to spare the thread a join, and a stale
  # one would misname an operator in the only place a customer never sees but an auditor does.
  def snapshot_display_name
    self.display_name = user.available_name if user.present?
  end

  def user_must_be_a_super_admin
    return if user.nil? || user.is_a?(SuperAdmin)

    errors.add(:user, 'must be a Lynomia super admin')
  end
end
