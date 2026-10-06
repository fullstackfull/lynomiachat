require 'rails_helper'

describe '/swagger', type: :request do
  describe 'GET /swagger' do
    it 'renders swagger index.html' do
      get '/swagger'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('redoc')
      expect(response.body).to include('/swagger.json')
    end

    it 'does not render files outside the swagger directory' do
      get '/swagger/%2Fetc%2Fpasswd'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /swagger on a deployed installation' do
    before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production')) }

    it 'does not publish the document to an anonymous caller' do
      get '/swagger/swagger.json'
      expect(response).to have_http_status(:not_found)
    end

    it 'does not publish it to a signed-in account administrator either' do
      account = create(:account)
      admin = create(:user, account: account, role: :administrator)
      sign_in(admin)
      get '/swagger/swagger.json'
      expect(response).to have_http_status(:not_found)
    end

    it 'serves it to a super admin' do
      sign_in(create(:super_admin), scope: :super_admin)
      get '/swagger/swagger.json'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Lynomia Chat')
    end
  end
end
