require 'rails_helper'

# Odoo's legacy JSON-RPC endpoint (custom/app/services/odoo/transport/json_rpc.rb). Present on every supported
# version, and the one Odoo's own 19.0 documentation schedules for removal in Odoo 22.
RSpec.describe Odoo::Transport::JsonRpc do
  subject(:transport) { described_class.new(profile, http: http) }

  include_context 'with commerce encryption'

  let(:profile) { build(:odoo_destination_profile, database: 'books', username: 'svc@example.com') }
  let(:http) { instance_double(Odoo::Http) }

  it 'asks for the version with no credentials at all' do
    allow(http).to receive(:post_json).and_return([200, { 'result' => { 'server_version' => '17.0' } }])

    transport.version

    expect(http).to have_received(:post_json) do |path, body|
      expect(path).to eq('/jsonrpc')
      expect(body[:params][:service]).to eq('common')
      expect(body[:params][:method]).to eq('version')
      expect(body.to_json).not_to include('odoo-api-key-factory')
    end
  end

  it 'authenticates once and reuses the uid for every later call' do
    allow(http).to receive(:post_json).and_return([200, { 'result' => 7 }], [200, { 'result' => [42] }],
                                                  [200, { 'result' => true }])

    transport.call(model: 'account.move', method: 'create', named: { vals_list: [{}] })
    transport.call(model: 'account.move', method: 'action_post', ids: [42])

    expect(http).to have_received(:post_json).exactly(3).times
  end

  # Odoo answers a bad credential with `false` rather than an error object, so the falsy answer IS the
  # failure and must not become a uid of `false` in the next call's arguments.
  it 'treats a falsy authenticate answer as a rejected credential' do
    allow(http).to receive(:post_json).and_return([200, { 'result' => false }])

    expect { transport.call(model: 'account.move', method: 'create') }
      .to raise_error(Odoo::Error) { |error| expect(error.code).to eq('AUTH_INVALID') }
  end

  # A BUSINESS REFUSAL ARRIVES AS HTTP 200 on this transport. Treating 200 as success would turn every Odoo
  # rejection into a silent no-op.
  it 'reads the error object out of a 200 response' do
    allow(http).to receive(:post_json).and_return(
      [200, { 'result' => 7 }],
      [200, { 'error' => { 'message' => 'Odoo Server Error',
                           'data' => { 'name' => 'odoo.exceptions.ValidationError', 'message' => 'Bad journal' } } }]
    )

    expect { transport.call(model: 'account.move', method: 'create') }
      .to raise_error(Odoo::Error) { |error| expect(error.code).to eq('BUSINESS_RULE') }
  end

  it 'routes a missing record to review rather than to a retry' do
    allow(http).to receive(:post_json).and_return(
      [200, { 'result' => 7 }],
      [200, { 'error' => { 'data' => { 'name' => 'odoo.exceptions.MissingError', 'message' => 'gone' } } }]
    )

    expect { transport.call(model: 'account.move', method: 'read', ids: [1]) }
      .to raise_error(Odoo::Error) { |error| expect(error.classification).to eq(:needs_review) }
  end
end
