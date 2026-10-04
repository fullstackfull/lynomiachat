module RequestExceptionHandler
  extend ActiveSupport::Concern

  QUERY_CANCELED_ERROR_MESSAGE_PATTERNS = [
    'ActiveRecord::QueryCanceled',
    'PG::QueryCanceled',
    'canceling statement due to statement timeout'
  ].freeze

  included do
    rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
    rescue_from CustomExceptions::Inbox::LimitExceeded,
                CustomExceptions::Account::EmailLimitExceeded,
                with: :render_error_response
  end

  private

  def handle_with_exception
    yield
  rescue ActiveRecord::RecordNotFound => e
    log_handled_error(e)
    render_not_found_error('Resource could not be found')
  rescue Pundit::NotAuthorizedError => e
    log_handled_error(e)
    render_unauthorized('You are not authorized to do this action')
  rescue ActionController::ParameterMissing => e
    log_handled_error(e)
    render_could_not_create_error(e.message)
  rescue ActiveRecord::QueryCanceled => e
    log_handled_error(e)
    render_could_not_create_error(database_query_canceled_message)
  ensure
    # to address the thread variable leak issues in Puma/Thin webserver
    Current.reset
  end

  def render_unauthorized(message)
    render json: { error: message }, status: :unauthorized
  end

  def render_not_found_error(message)
    render json: { error: message }, status: :not_found
  end

  def render_could_not_create_error(error)
    render json: { error: sanitized_error_message(error) }, status: :unprocessable_entity
  end

  def render_payment_required(message)
    render json: { error: message }, status: :payment_required
  end

  def render_internal_server_error(message)
    render json: { error: message }, status: :internal_server_error
  end

  def render_record_invalid(exception)
    log_handled_error(exception)
    errors = exception.record.errors
    render json: {
      message: errors.full_messages.join(', '),
      attributes: errors.attribute_names,
      # `message` joins every error with a comma, which a client cannot split back onto attributes: one
      # attribute can carry several errors, and a message can itself contain a comma. Keyed by attribute, a
      # form can put each message next to its own field.
      errors: errors_grouped_by_attribute(errors, &:full_message),
      # The validator that rejected it, so a client can tell "already taken" from "wrong format" — both of
      # which land on `phone_number` — and show its own localized sentence instead of an English one.
      error_types: errors_grouped_by_attribute(errors) { |error| error.type.to_s }
    }, status: :unprocessable_entity
  end

  def errors_grouped_by_attribute(errors, &)
    errors.group_by(&:attribute).transform_values { |attribute_errors| attribute_errors.map(&) }
  end

  def render_error_response(exception)
    log_handled_error(exception)
    render json: exception.to_hash, status: exception.http_status
  end

  def log_handled_error(exception)
    logger.info("Handled error: #{exception.inspect}")
  end

  def sanitized_error_message(message)
    return database_query_canceled_message if database_query_canceled_message?(message)

    message
  end

  def database_query_canceled_message?(message)
    error_message = message.to_s
    QUERY_CANCELED_ERROR_MESSAGE_PATTERNS.any? { |pattern| error_message.include?(pattern) }
  end

  def database_query_canceled_message
    I18n.t('errors.database.query_canceled')
  end
end
