# Staff authority on the Platform Support desk — the one layer the Operations console does not have
# (docs/platform-support/12-refresh-against-product-refinement.md §3 "Staff side").
#
# BEING A SUPER ADMIN IS NOT BEING SUPPORT STAFF. `authenticate_super_admin!` establishes that the caller
# administers this installation; it says nothing about whether they are one of the people who answer customers
# in Lynomia's name. So the staff controllers resolve an ACTIVE `PlatformSupport::Agent` row for
# `current_super_admin` and refuse when there is none. With no rows seeded anywhere, the desk refuses every
# staff action until an operator deliberately creates one, which is the correct fail-closed starting state.
#
# THIS IS NOT PUNDIT, deliberately. The Super Admin surface has no Pundit anywhere and this module does not
# install it: a second authorization framework on one surface is two places to look when something is allowed
# that should not be. It is a plain object the staff controllers' `before_action` builds.
#
# IT SHARES NO HELPER WITH THE TENANT POLICY, which is the session-isolation rule made structural. Warden keys
# both Devise scopes into one cookie, so one browser can hold a tenant session and a Super Admin session at
# once -- and the Super Admin navigation links straight to the agent dashboard, which is how an operator
# acquires both with one click. Nothing here reads `Current.user`, and nothing in PlatformSupport::TicketPolicy
# reads `current_super_admin`.
class PlatformSupport::StaffAuthorizer
  # The acting agent row for an authenticated Super Admin, or nil. Inactive rows answer nil: deactivating an
  # agent is how an operator leaves the desk, and it has to take effect without deleting their notes.
  #
  # Named `agent_for` rather than `resolve` so that nothing on this surface shares a method name with
  # PlatformSupport::TicketPolicy::Scope#resolve: the two authorization paths are not interchangeable, and a
  # shared name is the first step towards a caller treating them as if they were.
  def self.agent_for(super_admin)
    return nil if super_admin.nil?

    PlatformSupport::Agent.active.find_by(user_id: super_admin.id)
  end

  def initialize(agent)
    @agent = agent
  end

  attr_reader :agent

  def staff? = @agent.present?

  def lead? = @agent.present? && @agent.lead?

  # A lead may take a ticket off another agent. An agent may pick up unassigned work and hand back its own,
  # which is the whole of "work your own queue" without a second permission vocabulary.
  def may_assign?(ticket)
    return false if @agent.nil?

    lead? || ticket.assignee_id.nil? || ticket.assignee_id == @agent.id
  end

  # Thresholds are Lynomia's commercial commitment, so changing one is a lead's decision rather than any
  # operator's.
  def may_edit_sla_policies? = lead?
end
