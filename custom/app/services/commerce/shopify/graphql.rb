# The Shopify Admin GraphQL API of one shop, at the pinned Commerce::Shopify::Config::API_VERSION
# (docs/commerce/19-shopify-graphql-provider.md). Queries only. Every value travels as a GraphQL variable, never written
# into a document.
#
# HTTP 200 is not success: a response with top-level `errors` raises, whatever `data` holds. THROTTLED is RATE_LIMITED,
# ACCESS_DENIED is PROTECTED_DATA_NOT_APPROVED when Shopify says the app is not approved for protected customer data and
# PERMISSION_DENIED otherwise. HTTP errors are Commerce::HttpClient's (401 AUTH_INVALID, 429 RATE_LIMITED, 5xx
# STORE_UNAVAILABLE).
class Commerce::Shopify::Graphql
  PATH = "/admin/api/#{Commerce::Shopify::Config::API_VERSION}/graphql.json".freeze
  NOT_APPROVED = /not approved to (?:use|access)/i

  def initialize(shop, access_token)
    @http = Commerce::HttpClient.new(base_uri: URI("https://#{shop}"), log_tag: 'shopify', headers: { 'X-Shopify-Access-Token' => access_token })
  end

  def query(document, variables = {})
    @budget = nil
    body = @http.post_json(PATH, { query: document, variables: variables })
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless body.is_a?(Hash)

    @budget = budget(body.dig('extensions', 'cost'))
    raise error(Array(body['errors'])) if body['errors'].present?
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless body['data'].is_a?(Hash)

    body['data']
  end

  # For Commerce::Backoff: { retry_after: } when the shop's query budget cannot pay for another query like the last one
  # (Shopify's throttleStatus and the query's requested cost), else the HTTP Retry-After of a 429.
  def rate_limit = @budget || @http.rate_limit

  private

  def budget(cost)
    status = cost.is_a?(Hash) ? cost['throttleStatus'] : nil
    return unless status.is_a?(Hash)

    needed = cost['requestedQueryCost'].to_f
    available, restore_rate = status.values_at('currentlyAvailable', 'restoreRate').map(&:to_f)
    { retry_after: ((needed - available) / restore_rate).ceil } if available < needed && restore_rate.positive?
  end

  def error(errors)
    codes = errors.map { |error| error.is_a?(Hash) ? error.dig('extensions', 'code') : nil }
    return Commerce::Error.new('RATE_LIMITED') if codes.include?('THROTTLED')
    return access_denied(errors) if codes.include?('ACCESS_DENIED')
    return Commerce::Error.new('STORE_UNAVAILABLE', reason: 'shopify_internal_error') if codes.include?('INTERNAL_SERVER_ERROR')

    Commerce::Error.new('INVALID_RESPONSE', reason: 'graphql_error')
  end

  def access_denied(errors)
    not_approved = errors.any? { |error| error.is_a?(Hash) && error['message'].to_s.match?(NOT_APPROVED) }
    not_approved ? Commerce::Error.new('PROTECTED_DATA_NOT_APPROVED') : Commerce::Error.new('PERMISSION_DENIED')
  end
end
