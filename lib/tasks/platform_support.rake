# Who at Lynomia works the Platform Support desk.
#
# THIS IS THE ONLY WAY TO CREATE A `PlatformSupport::Agent`, deliberately, and it is a command the installation
# owner runs rather than a page anybody can reach:
#
#   * No row is seeded anywhere. Who answers customers in Lynomia's name is an owner decision, and a migration
#     that invented one would make the desk open to whoever happened to be in the `users` table
#     (docs/platform-support/12-refresh-against-product-refinement.md §11.3).
#   * A page that creates agent rows would itself need an agent row to protect it, or it would be open to every
#     Super Admin -- which is the distinction this module exists to draw. The desk refusing every action until
#     this task is run is the correct fail-closed starting state, not a gap.
#
# Being a Super Admin is NOT being support staff, so this grants the second thing to somebody who already has
# the first. An email that names no Super Admin fails loudly: a typo must not silently grant nobody.
#
# NO AUDIT ROW IS WRITTEN HERE. `Custom::AuditLog` records an actor, and the actor of a shell command is
# whoever holds the server -- not a `users` row, and attributing it to the person being granted would name the
# wrong party. Operator decisions ON a ticket are audited; who holds the server is answered by the server.
#
# Usage:
#   EMAIL=ops@example.com bundle exec rake platform_support:grant_agent
#   EMAIL=ops@example.com ROLE=lead bundle exec rake platform_support:grant_agent
#   EMAIL=ops@example.com bundle exec rake platform_support:revoke_agent
#   bundle exec rake platform_support:agents
namespace :platform_support do
  desc 'Grant the Platform Support desk to an existing Super Admin (EMAIL=, optional ROLE=agent|lead)'
  task grant_agent: :environment do
    email = ENV.fetch('EMAIL')
    role = ENV.fetch('ROLE', 'agent')
    raise "ROLE must be one of #{PlatformSupport::Agent.roles.keys.join(', ')}" unless PlatformSupport::Agent.roles.key?(role)

    super_admin = SuperAdmin.find_by!(email: email)
    agent = PlatformSupport::Agent.find_or_initialize_by(user_id: super_admin.id)
    agent.update!(role: role, active: true)

    puts "#{agent.display_name} <#{email}> now works the Platform Support desk as #{agent.role}."
  end

  # Deactivated, never deleted: an internal note is the record of a decision and must not lose its author, and
  # the agent's tickets stay assigned so the desk asks for a reassignment rather than losing them.
  desc 'Take the Platform Support desk away from a Super Admin, keeping their notes and history (EMAIL=)'
  task revoke_agent: :environment do
    email = ENV.fetch('EMAIL')
    agent = PlatformSupport::Agent.find_by!(user_id: SuperAdmin.find_by!(email: email).id)
    agent.update!(active: false)

    assigned = agent.assigned_tickets.where(status: PlatformSupport::Ticket::OPEN_STATUSES).count
    puts "#{agent.display_name} <#{email}> no longer works the desk. #{assigned} open ticket(s) still assigned to them."
  end

  desc 'Who works the Platform Support desk'
  task agents: :environment do
    rows = PlatformSupport::Agent.includes(:user).order(:display_name)
    puts 'No Platform Support agents. The desk refuses every staff action until one is granted.' if rows.empty?
    rows.each do |agent|
      columns = { name: agent.display_name, email: agent.user&.email, role: agent.role,
                  state: agent.active? ? 'active' : 'inactive' }
      puts format('%<name>-28s %<email>-32s %<role>-6s %<state>s', columns)
    end
  end
end
