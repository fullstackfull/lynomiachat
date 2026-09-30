require 'rails_helper'

RSpec.describe Commerce::Shopify::Graphql do
  include_context 'with shopify commerce app'

  let(:graphql) { described_class.new('lynomia-demo.myshopify.com', 'access-1') }
  let(:url) { 'https://lynomia-demo.myshopify.com/admin/api/2026-07/graphql.json' }
  let(:document) { 'query Q($first: Int!) { shop { id } }' }

  def respond_with(body)
    stub_request(:post, url).to_return(status: 200, body: body.to_json)
  end

  def error_for
    graphql.query(document, first: 1)
    nil
  rescue Commerce::Error => e
    e.as_json
  end

  it 'posts the document and its variables to the pinned version with the access token header only' do
    stub = stub_request(:post, url).with(body: { query: document, variables: { first: 1 } }.to_json,
                                         headers: { 'X-Shopify-Access-Token' => 'access-1', 'Content-Type' => 'application/json' })
                                   .to_return(status: 200, body: { data: { shop: { id: 'gid://shopify/Shop/1' } } }.to_json)

    expect(graphql.query(document, first: 1)).to eq('shop' => { 'id' => 'gid://shopify/Shop/1' })
    expect(stub).to have_been_requested.once
    expect(a_request(:post, url).with { |request| request.headers.key?('Authorization') }).not_to have_been_made
  end

  it 'treats top-level errors as failures even with HTTP 200 and data' do
    respond_with(data: { shop: nil }, errors: [{ message: 'Field does not exist', extensions: { code: 'undefinedField' } }])
    expect(error_for).to eq(code: 'INVALID_RESPONSE', reason: 'graphql_error')

    respond_with(data: nil)
    expect(error_for).to eq(code: 'INVALID_RESPONSE', reason: 'unexpected_shape')
  end

  it 'separates protected customer data that is not approved from other access denials' do
    respond_with(data: { customers: nil }, errors: [{ message: 'This app is not approved to access the Customer object. See https://shopify.dev.',
                                                      extensions: { code: 'ACCESS_DENIED' }, path: ['customers'] }])
    expect(error_for).to eq(code: 'PROTECTED_DATA_NOT_APPROVED')

    respond_with(data: { customers: { nodes: [{ defaultEmailAddress: nil }] } },
                 errors: [{ message: 'This app is not approved to use the email field.', extensions: { code: 'ACCESS_DENIED' } }])
    expect(error_for).to eq(code: 'PROTECTED_DATA_NOT_APPROVED')

    respond_with(data: nil, errors: [{ message: 'Access denied for orders field.', extensions: { code: 'ACCESS_DENIED' } }])
    expect(error_for).to eq(code: 'PERMISSION_DENIED')
  end

  it 'maps throttling to RATE_LIMITED and reports how long the budget needs to recover' do
    throttle = { maximumAvailable: 2000.0, currentlyAvailable: 2, restoreRate: 100.0 }
    respond_with(errors: [{ message: 'Throttled', extensions: { code: 'THROTTLED' } }],
                 extensions: { cost: { requestedQueryCost: 202, throttleStatus: throttle } })

    expect(error_for).to eq(code: 'RATE_LIMITED')
    expect(graphql.rate_limit).to eq(retry_after: 2)
  end

  it 'reports a low budget after a successful query, and nothing while the budget can pay for another one' do
    low = { maximumAvailable: 2000.0, currentlyAvailable: 30, restoreRate: 100.0 }
    respond_with(data: { shop: {} }, extensions: { cost: { requestedQueryCost: 150, actualQueryCost: 40, throttleStatus: low } })
    graphql.query(document)
    expect(graphql.rate_limit).to eq(retry_after: 2)

    ample = { maximumAvailable: 2000.0, currentlyAvailable: 1960, restoreRate: 100.0 }
    respond_with(data: { shop: {} }, extensions: { cost: { requestedQueryCost: 150, actualQueryCost: 40, throttleStatus: ample } })
    graphql.query(document)
    expect(graphql.rate_limit[:retry_after]).to be_nil
  end

  it 'maps HTTP failures through the Commerce client' do
    stub_request(:post, url).to_return(status: 401, body: '{"errors":"[API] Invalid API key or access token"}')
    expect(error_for).to eq(code: 'AUTH_INVALID')

    stub_request(:post, url).to_return(status: 429, headers: { 'Retry-After' => '2' })
    expect(error_for).to eq(code: 'RATE_LIMITED')
    expect(graphql.rate_limit).to include(retry_after: 2)

    respond_with({ errors: [{ message: 'Internal error', extensions: { code: 'INTERNAL_SERVER_ERROR' } }] })
    expect(error_for).to eq(code: 'STORE_UNAVAILABLE', reason: 'shopify_internal_error')
  end
end
