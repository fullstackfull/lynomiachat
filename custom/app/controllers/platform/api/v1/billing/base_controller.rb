# frozen_string_literal: true

# Base for the billing Platform API: /platform/api/v1/billing/...
#
# Authentication: header `api_access_token: <token>` of a Platform App
# (Super Admin -> Platform Apps). Platform App tokens get full billing access.
class Platform::Api::V1::Billing::BaseController < ActionController::API
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  before_action :authenticate_platform_app!

  rescue_from ActiveRecord::RecordNotFound do
    render_error('not_found', 'Resource not found', :not_found)
  end

  rescue_from ActionController::ParameterMissing do |e|
    render_error('invalid_params', e.message, :unprocessable_entity)
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render_error('invalid_record', e.record.errors.full_messages.to_sentence, :unprocessable_entity)
  end

  private

  # Rails stores headers with underscores as HTTP_API_ACCESS_TOKEN
  def authenticate_platform_app!
    token = request.headers['HTTP_API_ACCESS_TOKEN'].presence || request.headers['api_access_token'].presence
    owner = token && AccessToken.find_by(token: token)&.owner
    @platform_app = owner if owner.is_a?(PlatformApp)
    return if @platform_app

    render_error('unauthorized', 'A valid Platform App access token is required.', :unauthorized)
  end

  def render_data(data, status: :ok, meta: nil)
    body = { data: data }
    body[:meta] = meta if meta
    render json: body, status: status
  end

  def render_error(code, message, status)
    render json: { error: code, message: message }, status: status
  end

  # ?page=1&per_page=25 (max 100)
  def render_subscriptions_page(scope)
    page = [params[:page].to_i, 1].max
    per_page = params[:per_page].to_i
    per_page = DEFAULT_PER_PAGE unless per_page.positive?
    per_page = [per_page, MAX_PER_PAGE].min

    total = scope.count
    records = scope.includes(:account, :plan).offset((page - 1) * per_page).limit(per_page)
    render_data(
      records.map { |subscription| ::Billing::ApiSerializer.subscription(subscription) },
      meta: { page: page, per_page: per_page, total: total, total_pages: (total.to_f / per_page).ceil }
    )
  end

  # ?status=active,trialing  -> ["active", "trialing"]
  def list_param(key)
    Array(params[key]).flat_map { |value| value.to_s.split(',') }.map(&:strip).compact_blank
  end

  # Runs the Stripe product/price sync and reports the result instead of failing the request
  def stripe_sync(plan)
    ::Billing::PlanSync.new(plan).perform
    { ok: true }
  rescue ::Billing::PlanSync::NotConfigured, Stripe::StripeError => e
    { ok: false, error: e.message }
  end
end