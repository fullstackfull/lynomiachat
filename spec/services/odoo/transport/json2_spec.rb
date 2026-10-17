require 'rails_helper'

# Odoo 19's External JSON-2 API, as this adapter speaks it (custom/app/services/odoo/transport/json2.rb).
#
# NO NETWORK HERE. Odoo::Http is doubled, so these examples are about what the transport SENDS and how it
# reads an answer -- which is the part a wrong assumption about Odoo would get wrong.
RSpec.describe Odoo::Transport::Json2 do
  subject(:transport) { described_class.new(profile, http: http) }

  include_context 'with commerce encryption'

  let(:profile) { build(:odoo_destination_profile, database: 'books', username: 'svc@example.com') }
  let(:http) { instance_double(Odoo::Http) }

  it 'posts to /json/2/<model>/<method> with the key in an Authorization header, never in the body' do
    allow(http).to receive(:post_json).and_return([200, [42]])

    transport.call(model: 'account.move', method: 'create', named: { vals_list: [{ 'ref' => 'x' }] })

    expect(http).to have_received(:post_json) do |path, body, headers:|
      expect(path).to eq('/json/2/account.move/create')
      expect(headers['Authorization']).to eq('Bearer odoo-api-key-factory')
      expect(headers['X-Odoo-Database']).to eq('books')
      expect(body.to_json).not_to include('odoo-api-key-factory')
      expect(body[:vals_list]).to eq([{ 'ref' => 'x' }])
    end
  end

  it 'carries allowed_company_ids on every call, which is what pins a write to one company' do
    allow(http).to receive(:post_json).and_return([200, true])

    transport.call(model: 'account.move', method: 'action_post', ids: [1])

    expect(http).to have_received(:post_json) do |_path, body, **|
      expect(body[:context]['allowed_company_ids']).to eq([profile.company_id])
      expect(body[:ids]).to eq([1])
    end
  end

  # A 404 is a statement about the TRANSPORT -- this server has no JSON-2 route -- so the caller re-detects
  # the version rather than reporting the document as broken.
  it 'classifies a 404 as a missing endpoint rather than a missing record' do
    allow(http).to receive(:post_json).and_return([404, {}])

    expect { transport.call(model: 'account.move', method: 'create') }
      .to raise_error(Odoo::Error) { |error| expect(error.code).to eq('ENDPOINT_MISSING') }
  end

  it 'maps the HTTP statuses Odoo answers with onto our own classifications' do
    {
      401 => [:permanent, 'AUTH_INVALID'], 403 => [:permanent, 'PERMISSION_DENIED'],
      422 => [:permanent, 'INVALID_REQUEST'], 429 => [:transient, 'RATE_LIMITED'],
      503 => [:transient, 'SERVER_ERROR']
    }.each do |status, (classification, code)|
      allow(http).to receive(:post_json).and_return([status, {}])

      expect { transport.call(model: 'account.move', method: 'create') }.to raise_error(Odoo::Error) do |error|
        expect(error.code).to eq(code)
        expect(error.classification).to eq(classification)
      end
    end
  end

  it 'maps an Odoo business refusal to a permanent failure and keeps its message out of the error text' do
    allow(http).to receive(:post_json).and_return(
      [400, { 'name' => 'odoo.exceptions.UserError', 'message' => 'Journal should be of type sale.',
              'debug' => 'Traceback... api_key=odoo-api-key-factory' }]
    )

    expect { transport.call(model: 'account.move', method: 'action_post', ids: [1]) }
      .to raise_error(Odoo::Error) do |error|
        expect(error.code).to eq('BUSINESS_RULE')
        expect(error.classification).to eq(:permanent)
        expect(error.message).not_to include('Journal should be')
        expect(error.detail).to include('Journal should be of type sale.')
        expect(error.as_json.to_json).not_to include('Journal should be')
      end
  end
end
