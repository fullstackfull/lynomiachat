require 'rails_helper'

describe '/manifest.json', type: :request do
  # InstallationConfig rows roll back with the transaction, but GlobalConfig caches them in Redis, which does
  # not. Clearing it here keeps a value set for one example out of the next one.
  after { GlobalConfig.clear_cache }

  # `response.parsed_body` only parses registered JSON media types, and the manifest is served as the
  # spec-correct application/manifest+json, so it comes back as a String.
  let(:manifest) { JSON.parse(response.body) } # rubocop:disable Rails/ResponseParsedBody

  before do
    InstallationConfig.where(name: 'INSTALLATION_NAME').first_or_create(value: 'Acme Desk').update!(value: 'Acme Desk')
    GlobalConfig.clear_cache
  end

  it 'names the web app after the installation rather than a hard-coded product name' do
    get '/manifest.json'

    expect(response).to have_http_status(:success)
    expect(manifest['name']).to eq('Acme Desk')
    expect(manifest['short_name']).to eq('Acme')
  end

  it 'keeps the icon set and display options the static manifest shipped' do
    get '/manifest.json'

    expect(manifest['icons'].pluck('src')).to include('/android-icon-192x192.png')
    expect(manifest['start_url']).to eq('/')
    expect(manifest['display']).to eq('standalone')
  end
end
