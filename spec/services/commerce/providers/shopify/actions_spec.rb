require 'rails_helper'

# Shopify order actions (docs/commerce/29-provider-action-capabilities.md §Shopify): GraphQL 2026-07 only, write_orders
# only after an explicit reconnect. Order shapes are the documented-shape fixtures plus the action fields.
RSpec.describe Commerce::Providers::Shopify::Actions do
  include_context 'with commerce encryption'
  include_context 'with shopify commerce app'

  let(:store) do
    credentials = { 'access_token' => 'shpat_write', 'refresh_token' => 'shprt_write', 'scope' => 'read_customers,write_orders',
                    'access_token_expires_at' => 1.hour.from_now.utc.iso8601, 'refresh_token_expires_at' => 90.days.from_now.utc.iso8601 }
    create(:commerce_store, :shopify, external_store_id: '68210001', base_url: 'https://lynomia-demo.myshopify.com', credentials: credentials)
  end
  let(:provider) { Commerce::Providers.for(store) }
  let(:graphql) { 'https://lynomia-demo.myshopify.com/admin/api/2026-07/graphql.json' }
  let(:orders) do
    JSON.parse(file_fixture('commerce/shopify/orders.json').read).dig('data', 'orders', 'nodes').index_by { |order| order['legacyResourceId'] }
  end
  let(:paid) do
    orders['6001006'].merge(
      'refundable' => true, 'presentmentCurrencyCode' => 'SAR', 'totalRefundedSet' => { 'presentmentMoney' => { 'amount' => '0.0' } },
      'suggestedRefund' => {
        'maximumRefundableSet' => { 'presentmentMoney' => { 'amount' => '520.0' } },
        'suggestedTransactions' => [{ 'kind' => 'SUGGESTED_REFUND', 'gateway' => 'shopify_payments', 'formattedGateway' => 'Shopify Payments',
                                      'parentTransaction' => { 'id' => 'gid://shopify/OrderTransaction/91' },
                                      'maximumRefundableSet' => { 'presentmentMoney' => { 'amount' => '500.0' } } }]
      },
      'refunds' => []
    )
  end
  let(:unpaid) do
    orders['6001005'].merge('displayFulfillmentStatus' => 'UNFULFILLED', 'refundable' => false, 'presentmentCurrencyCode' => 'SAR',
                            'totalRefundedSet' => { 'presentmentMoney' => { 'amount' => '0.0' } }, 'suggestedRefund' => nil, 'refunds' => [])
  end
  let(:key) { "commerce-action:#{SecureRandom.uuid}" }
  let(:sent) { [] }
  let(:answer_with) do
    lambda do |order, mutation = nil, status: 200|
      stub_request(:post, graphql).to_return do |request|
        body = JSON.parse(request.body)
        sent << body
        job = { data: { job: { id: 'gid://shopify/Job/1', done: true } } }
        next { status: 200, body: { data: { order: order } }.to_json } if body['query'].include?('query LynomiaOrderActions')
        next { status: 200, body: job.to_json } if body['query'].include?('query LynomiaJob')

        { status: status, body: mutation.to_json }
      end
    end
  end
  let(:snapshot) { ->(order) { answer_with.call(order) && provider.action_snapshot(order['legacyResourceId']) } }
  let(:run) do
    lambda do |action_type, **attributes|
      Commerce::ActionRun.create!(account: store.account, store: store, provider: 'shopify', action_type: action_type,
                                  external_resource_id: '6001006', idempotency_key: key, request_digest: 'd' * 64, status: :unknown,
                                  started_at: 10.minutes.ago, **attributes)
    end
  end

  it 'offers a paid order its refund up to what its payment can return, and no cancellation' do
    capabilities = snapshot.call(paid).capabilities

    expect(capabilities).to eq(
      'cancel_order' => { available: false, reason: 'paid_refund_first' },
      'refund_full' => { available: true, max_amount: '500.00', currency: 'SAR', mode: 'gateway', gateway: 'Shopify Payments' },
      'refund_partial' => { available: true, max_amount: '500.00', currency: 'SAR', mode: 'gateway', gateway: 'Shopify Payments' }
    )
    expect(sent.first['query']).to include('suggestedRefund(suggestFullRefund: true)').and(include('refunds(first: 20)'))
    expect(sent.first['query']).not_to include('address', 'phone')
  end

  it 'cancels only unpaid, unfulfilled, uncancelled orders, and refunds no split payment' do
    expect(snapshot.call(unpaid).capabilities['cancel_order']).to eq(available: true, restocks: true, refunds: false)
    expect(snapshot.call(unpaid).capabilities['refund_full']).to eq(available: false, reason: 'not_paid')
    expect(snapshot.call(orders['6001003'].merge(unpaid.slice('refundable', 'suggestedRefund', 'refunds'))).capabilities['cancel_order'])
      .to eq(available: false, reason: 'already_cancelled')

    split = paid.deep_dup.tap { |order| order['suggestedRefund']['suggestedTransactions'] *= 2 }
    expect(snapshot.call(split).capabilities['refund_partial']).to eq(available: false, reason: 'multiple_payments')
  end

  it 'cancels through a Shopify Job, without refunding or notifying, and follows the Job' do
    cancelled = { orderCancel: { job: { id: 'gid://shopify/Job/1', done: false }, orderCancelUserErrors: [], userErrors: [] } }
    answer_with.call(unpaid, { data: cancelled })
    result = provider.perform_action('cancel_order', provider.action_snapshot('6001005'), { 'reason' => 'inventory', 'restock' => true }, key)

    expect(result).to eq(Commerce::ActionResult.running('gid://shopify/Job/1'))
    mutation = sent.last
    expect(mutation['query']).to include('orderCancel(').and(include('refund: false')).and(include('notifyCustomer: false'))
    expect(mutation['variables']).to eq('orderId' => unpaid['id'], 'reason' => 'INVENTORY', 'restock' => true, 'staffNote' => "Lynomia #{key}")
  end

  it 'refunds once with Shopify\'s idempotency key, through the order\'s payment, the key also in the note' do
    answer_with.call(paid, { data: { refundCreate: { refund: { id: 'gid://shopify/Refund/7', legacyResourceId: '7' }, userErrors: [] } } })
    result = provider.perform_action('refund_partial', provider.action_snapshot('6001006'), { 'amount' => '120.00', 'reason' => 'damaged' }, key)

    expect(result).to eq(Commerce::ActionResult.succeeded('7'))
    mutation = sent.last
    expect(mutation['query']).to include('refundCreate(input: $input) @idempotent(key: $idempotencyKey)')
    expect(mutation['variables']).to eq(
      'idempotencyKey' => key,
      'input' => { 'orderId' => paid['id'], 'currency' => 'SAR', 'notify' => false, 'note' => "Lynomia #{key}",
                   'transactions' => [{ 'orderId' => paid['id'], 'amount' => '120.00', 'gateway' => 'shopify_payments', 'kind' => 'REFUND',
                                        'parentId' => 'gid://shopify/OrderTransaction/91' }] }
    )
    expect(sent.count { |body| body['query'].include?('mutation') }).to eq(1)
  end

  it 'reads HTTP 200 with errors, userErrors and HTTP failures as what they prove' do
    snap = snapshot.call(paid)
    {
      [200, { data: { refundCreate: { refund: nil, userErrors: [{ message: 'x' }] } } }] => Commerce::ActionResult.failed('PROVIDER_REJECTED'),
      [200, { errors: [{ message: 'Throttled', extensions: { code: 'THROTTLED' } }] }] => Commerce::ActionResult.failed('RATE_LIMITED'),
      [200, { errors: [{ message: 'Parse error' }] }] => Commerce::ActionResult.failed('PROVIDER_REJECTED'),
      [200, { errors: [{ message: 'Internal error', extensions: { code: 'INTERNAL_SERVER_ERROR' } }] }] => Commerce::ActionResult.unknown,
      [200, { data: { refundCreate: nil } }] => Commerce::ActionResult.unknown,
      [401, {}] => Commerce::ActionResult.failed('AUTH_INVALID'), [503, {}] => Commerce::ActionResult.unknown
    }.each do |(status, body), expected|
      answer_with.call(paid, body, status: status)
      expect(provider.perform_action('refund_partial', snap, { 'amount' => '1.00', 'reason' => 'other' }, key)).to eq(expected)
    end
  end

  it 'learns that the token may not write orders from Shopify\'s ACCESS_DENIED' do
    answer_with.call(paid, { errors: [{ message: 'Access denied for refundCreate field.', extensions: { code: 'ACCESS_DENIED' } }] })

    result = provider.perform_action('refund_partial', provider.action_snapshot('6001006'), { 'amount' => '1.00', 'reason' => 'other' }, key)

    expect(result).to eq(Commerce::ActionResult.failed('WRITE_ACCESS_DENIED'))
    expect(Commerce::Providers.for(store.reload).write_access_problem).to eq('missing_scope')
  end

  it 'reports a lost answer as unknown, never sending the mutation again' do
    snap = snapshot.call(paid)
    stub_request(:post, graphql).with { |request| request.body.include?('mutation') }.to_raise(Net::ReadTimeout)

    expect { provider.perform_action('refund_partial', snap, { 'amount' => '1.00', 'reason' => 'other' }, key) }
      .to raise_error(Commerce::Error) { |error| expect(error.reason).to eq('unknown_outcome') }
    expect(a_request(:post, graphql).with { |request| request.body.include?('mutation') }).to have_been_made.once
  end

  describe 'reconciling, by reading only' do
    it 'finds the refund by its note, or calls it not applied once settled with no refund since' do
      answer_with.call(paid.merge('refunds' => [{ 'id' => 'gid://shopify/Refund/7', 'legacyResourceId' => '7', 'note' => "Lynomia #{key}",
                                                  'createdAt' => 9.minutes.ago.utc.iso8601 }]))
      expect(provider.reconcile_action(run.call('refund_partial'), provider.action_snapshot('6001006'))).to eq(Commerce::ActionResult.succeeded('7'))

      answer_with.call(paid)
      not_applied = provider.reconcile_action(Commerce::ActionRun.sole, provider.action_snapshot('6001006'))
      expect(not_applied).to eq(Commerce::ActionResult.failed('NOT_APPLIED'))
      expect(sent.none? { |body| body['query'].include?('mutation') }).to be(true)
    end

    it 'follows a cancellation until the order shows it, or its Job ends without it' do
      cancel = run.call('cancel_order', status: :running, provider_request_id: 'gid://shopify/Job/1')
      answer_with.call(unpaid.merge('cancelledAt' => Time.current.utc.iso8601))
      expect(provider.reconcile_action(cancel, provider.action_snapshot('6001005'))).to eq(Commerce::ActionResult.succeeded)

      answer_with.call(unpaid)
      expect(provider.reconcile_action(cancel, provider.action_snapshot('6001005'))).to eq(Commerce::ActionResult.failed('NOT_APPLIED'))
    end
  end

  it 'has write access only with write_orders, which a read-only connection never holds' do
    expect(provider.write_access_problem).to be_nil

    store.update!(credentials: store.credentials.merge('scope' => 'read_customers,read_orders'))
    expect(Commerce::Providers.for(store).write_access_problem).to eq('missing_scope')
  end
end
