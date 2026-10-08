require 'rails_helper'

RSpec.describe 'API Base', type: :request do
  describe 'request to api base url' do
    it 'returns api version' do
      get '/api/'
      expect(response).to have_http_status(:success)
      expect(response.body).to include(Chatwoot.config[:version])
      expect(response.body).to include('queue_services')
      expect(response.body).to include('data_services')
    end

    # The readiness probe: a monitor reads the status code, so a dependency that is down has to change it.
    it 'reports service unavailable when the queue backend cannot be reached' do
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)

      get '/api/'

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to include('queue_services' => 'failing', 'data_services' => 'ok')
    end

    it 'reports service unavailable for a queue failure that is not a connection error' do
      allow(Redis).to receive(:new).and_raise(Redis::TimeoutError)

      get '/api/'

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to include('queue_services' => 'failing')
    end

    it 'reports service unavailable when the database cannot be reached' do
      allow(ActiveRecord::Base.connection).to receive(:select_value).and_raise(ActiveRecord::ConnectionNotEstablished)

      get '/api/'

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to include('data_services' => 'failing')
    end

    # A pooled connection left stale by a Postgres restart reports itself inactive even though the next query
    # reconnects and succeeds. Draining a healthy instance on that is worse than the blip it reacts to, so the
    # probe asks the database a question instead of asking the pool what it remembers.
    it 'stays ready when a stale pooled connection would reconnect on the next query' do
      allow(ActiveRecord::Base.connection).to receive(:active?).and_return(false)

      get '/api/'

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('data_services' => 'ok')
    end
  end
end
