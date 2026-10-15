require 'rails_helper'

# THE PRODUCER HALF OF THE SECOND CROSS-REPOSITORY CONTRACT, and it exists because the first
# one did not cover this endpoint and the same failure happened again.
#
# WHAT WENT WRONG. Store Syria resolves WHICH of the account's Lynomia commerce stores is
# itself before it can ask for a store-scoped audience count: it reads this endpoint's
# `stores` array and looks for the row whose provider is `storesyria` and whose
# `external_store_id` is its own id. This endpoint never emitted `external_store_id`. The
# match was therefore always false, `commerce_store_id` never reached Lynomia, and every
# "customers of this store" figure silently fell back to the account-wide one -- the whole
# P5B store scope, dead on the only path built to drive it.
#
# AND WHY NO TEST SAW IT. Lynomia's own spec asserted the three keys it emitted. Store
# Syria's fake injected a fourth key of its own invention and asserted the behaviour that
# followed. Both were green. That is the identical shape as the consent-feed defect that
# motivated the first contract artifact: two mocks agreeing with their own authors.
#
# SO THE ARTIFACT IS THE AGREEMENT. docs/contracts/audience_fields.v1.json is the real
# response of the real endpoint, normalised only for deployment-specific ids. The consumer
# repository holds a byte-identical copy and drives its REAL store-resolution with it
# (storesyria/tests/Contract/LynomiaAudienceFieldsContractTest.php). Neither side can change
# the shape alone without a test going red.
RSpec.describe 'audience_fields contract', type: :request do
  include_context 'with commerce encryption'

  # Locals rather than constants: a constant assigned inside this block lands on Object, and
  # both are read in the examples through the closure anyway.
  contract_path = Rails.root.join('docs/contracts/audience_fields.v1.json')
  # Asserted identically in the consumer repository. Changing the artifact means changing
  # this value in BOTH places, which is the point.
  contract_sha256 = '46382538cef05d7125b2bf4cd58b734d3029791e2150f5b721cb537e4d92ed8f'

  let(:artifact) { JSON.parse(contract_path.read) }
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:store) do
    create(:commerce_store, account: account, provider: 'storesyria', name: 'Damascus Linens',
                            external_store_id: '4242', status: :active)
  end

  before do
    account.enable_features!('lynomia_commerce')
    # BOTH switches, because `counted_stores` honours both: the installation has to offer
    # the provider and the account has to be entitled to Commerce. A store of a provider the
    # installation has switched off is not counted, which is the rule Customer 360 applies.
    create(:installation_config, name: 'STORESYRIA_ENABLED', value: true)
    contact = create(:contact, account: account)
    create(:commerce_customer_link, account: account, store: store, contact: contact, external_customer_id: 'cust-77')
  end

  # Deployment-specific ids are the only values normalised, because they differ between any
  # two installations and are not part of the agreement.
  def normalise(body)
    body = body.deep_dup
    body['stores'].each { |row| row['id'] = 5101 }
    body
  end

  it 'is the artifact the consumer repository holds, byte for byte' do
    expect(Digest::SHA256.hexdigest(contract_path.read)).to eq(contract_sha256),
                                                            'the contract artifact changed; copy it to ' \
                                                            'storesyria/tests/Contract/lynomia/ and update ' \
                                                            'the sha in both repositories'
  end

  it 'still emits the store list exactly as the contract records it' do
    get "/api/v1/accounts/#{account.id}/commerce/audience_fields",
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(normalise(response.parsed_body)).to eq(artifact['sample'])
  end

  # THE FIELD THE CONSUMER MATCHES ON, called out separately because its absence is the
  # defect that motivated this artifact. A store row without it cannot be recognised by the
  # installation it belongs to, and the store scope silently becomes account-wide.
  it 'names each store’s id in its own platform, because the consumer matches on it' do
    artifact['sample']['stores'].each do |row|
      expect(row).to include('provider', 'external_store_id')
      expect(row['external_store_id']).to be_a(String).and(be_present)
    end
  end
end
