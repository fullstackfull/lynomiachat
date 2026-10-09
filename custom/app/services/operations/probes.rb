# What can be read live, this request (docs/p9/04-operations-center.md §probes).
#
# Deliberately cheap: one `SELECT 1`, one Redis PING, one Sidekiq process-set read, and three values already in
# memory. No shell command, no provider call, no table scan. An operator opening a page must not cost the
# installation anything it would notice.
#
# The existing Super Admin Instance Status page reads the same four facts
# (app/controllers/super_admin/instance_statuses_controller.rb) and keeps its own fuller Redis dump. This is not
# a refactor of that page: the console links to it for the detail and reads only what it needs here. The overlap
# is one query and one PING, and rewriting an OSS controller to share them would be a larger change than the
# duplication it removes.
class Operations::Probes
  def call
    [database, redis, workers]
  end

  # Three values with no health of their own: what is deployed, and whether a migration is waiting. A pending
  # migration IS a warning, because it means the running code and the schema disagree.
  def release
    {
      version: Chatwoot.config[:version],
      git_sha: defined?(GIT_HASH) ? GIT_HASH : nil,
      edition: ChatwootApp.custom? ? 'Custom' : 'Community',
      extensions: ChatwootApp.extensions
    }.compact
  end

  def migrations
    # The same two lines the existing Instance Status page uses
    # (app/controllers/super_admin/instance_statuses_controller.rb#instance_meta); `connection.migration_context`
    # does not exist on Rails 7.2 and silently turned this probe into `unknown`.
    context = ActiveRecord::MigrationContext.new(ActiveRecord::Migrator.migrations_paths)
    pending = context.needs_migration?
    Operations::Health::Component.build(
      key: :migrations, source_class: 'probed', observed_at: Time.current,
      status: pending ? Operations::Health::WARNING : Operations::Health::HEALTHY,
      reason: pending ? 'A database migration is pending' : nil
    )
  rescue StandardError => e
    unreachable(:migrations, e)
  end

  private

  def database
    ActiveRecord::Base.connection.select_value('SELECT 1')
    healthy(:database)
  rescue StandardError => e
    unreachable(:database, e)
  end

  def redis
    client = Redis.new(Redis::Config.app)
    return unreachable(:redis, nil, 'Redis did not answer PING') unless client.ping == 'PONG'

    info = client.info
    healthy(:redis, detail: { used_memory: info['used_memory_human'], clients: info['connected_clients'].to_i })
  rescue StandardError => e
    unreachable(:redis, e)
  end

  # No registered process means nothing async is happening at all: no WhatsApp send, no commerce sync, no
  # campaign, no SLA sweep. That is the one probe that is critical rather than a warning.
  def workers
    require 'sidekiq/api'
    processes = Sidekiq::ProcessSet.new.size
    stats = Sidekiq::Stats.new
    detail = { processes: processes, enqueued: stats.enqueued, scheduled: stats.scheduled_size,
               retrying: stats.retry_size, dead: stats.dead_size }
    return healthy(:workers, detail: detail) if processes.positive?

    Operations::Health::Component.build(
      key: :workers, status: Operations::Health::CRITICAL, source_class: 'probed', observed_at: Time.current,
      reason: 'No Sidekiq process is registered', detail: detail, investigate: '/super_admin/monitoring/sidekiq'
    )
  rescue StandardError => e
    unreachable(:workers, e)
  end

  def healthy(key, detail: {})
    Operations::Health::Component.build(key: key, status: Operations::Health::HEALTHY, source_class: 'probed',
                                        observed_at: Time.current, detail: detail)
  end

  # A probe that could not run is UNKNOWN, never critical: we failed to look, which is not the same as having
  # looked and found it broken.
  def unreachable(key, error, reason = nil)
    Operations::Health::Component.build(
      key: key, status: Operations::Health::UNKNOWN, source_class: 'probed', observed_at: Time.current,
      reason: reason || "Could not be read (#{error&.class})"
    )
  end
end
