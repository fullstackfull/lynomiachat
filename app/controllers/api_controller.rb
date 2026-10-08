class ApiController < ApplicationController
  skip_before_action :set_current_user, only: [:index]

  # The readiness probe. /health answers whether the process is alive; this answers whether it can actually serve,
  # so a failing dependency has to show in the status code -- a monitor reads that, not the body.
  def index
    body = { version: Chatwoot.config[:version],
             timestamp: Time.now.utc.to_fs(:db),
             queue_services: redis_status,
             data_services: postgres_status }
    ready = body.values_at(:queue_services, :data_services).all?('ok')

    render json: body, status: ready ? :ok : :service_unavailable
  end

  private

  # Any failure to reach the dependency is a failure to report, not an exception to raise: a probe that 500s tells the
  # operator less than one that says which dependency is down.
  def redis_status
    Redis.new(Redis::Config.app).ping ? 'ok' : 'failing'
  rescue Redis::BaseError
    'failing'
  end

  # A real query, not `connection.active?`: that only reports the pool's own view of a cached connection, and a
  # connection left stale by a Postgres restart or an idle timeout reads as inactive even though the next request
  # would reconnect and succeed. Reporting that as `failing` would drain a healthy instance out of rotation.
  # `select_value` leases the connection, reconnects a stale one, and raises only if Postgres is really unreachable.
  def postgres_status
    ActiveRecord::Base.connection.select_value('SELECT 1') == 1 ? 'ok' : 'failing'
  rescue ActiveRecord::ActiveRecordError
    'failing'
  end
end
