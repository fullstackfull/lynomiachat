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

  def postgres_status
    ActiveRecord::Base.connection.active? ? 'ok' : 'failing'
  rescue ActiveRecord::ActiveRecordError
    'failing'
  end
end
