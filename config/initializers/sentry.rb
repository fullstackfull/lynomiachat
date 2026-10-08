if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.enabled_environments = %w[staging production]

    # To activate performance monitoring, set one of these options.
    # We recommend adjusting the value in production:
    config.traces_sample_rate = 0.1 if ENV['ENABLE_SENTRY_TRANSACTIONS']

    config.excluded_exceptions += ['Rack::Timeout::RequestTimeoutException', 'MutexApplicationJob::LockAcquisitionError']

    # to track post data in sentry
    # Off unless asked for. send_default_pii ships the request body, every cookie and the Authorization and
    # api_access_token headers to Sentry, and filter_parameters cannot redact any of them -- so a Sentry incident
    # would hand over live session and API credentials. Explicitly set user context instead; that still reaches
    # Sentry with this off.
    config.send_default_pii = ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_SENTRY_PII', false))
  end
end
