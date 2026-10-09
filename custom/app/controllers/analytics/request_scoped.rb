# Shared plumbing for every Lynomia Analytics controller (docs/p8/01-architecture.md).
#
# It lives in controllers/analytics/ rather than controllers/concerns/ on purpose. config/application.rb:46 adds
# eager load paths with `Dir["#{Rails.root}/custom/app/**"]`, and that glob is single level, so the roots are the
# immediate children of custom/app and nothing deeper. Under the custom/app/controllers root a file in a
# `concerns/` subdirectory therefore resolves as Concerns::Analytics::RequestScoped, because `concerns` is an
# ordinary path segment here and not the special autoload root Rails makes of app/controllers/concerns. Verified
# by booting: the constant was missing under concerns/ and resolved as Concerns::Analytics::RequestScoped.
#
# The account is taken from `Current.account`, which Api::V1::Accounts::BaseController has already resolved from
# the authenticated session and the route. `params[:account_id]` is never read here: it is the route's own
# segment, already validated upstream, and re-reading it would create a second, weaker source of truth for which
# tenant the query belongs to.
#
# Validation failures raise CustomExceptions::Analytics::*, which carry http_status 422, so an unusable filter or
# an inverted range answers with its reason instead of reaching a query or Sentry.
module Analytics::RequestScoped
  extend ActiveSupport::Concern

  included do
    rescue_from CustomExceptions::Analytics::Base, with: :render_analytics_error
  end

  private

  def date_range
    @date_range ||= Analytics::DateRange.new(
      account: Current.account,
      since: params[:since],
      until_value: params[:until],
      group_by: params[:group_by]
    )
  end

  def filter_set(family)
    Analytics::FilterSet.new(account: Current.account, family: family, params: filter_params)
  end

  def filter_params
    params.permit(*Analytics::MetricFamily::ALL_FILTERS).to_h
  end

  def render_analytics_error(exception)
    Rails.logger.info("Analytics request rejected: #{exception.class.name}")
    render json: exception.to_hash, status: exception.http_status
  end
end
