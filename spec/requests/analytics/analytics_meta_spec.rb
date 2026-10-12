require 'rails_helper'

RSpec.describe 'Analytics meta', type: :request do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'America/New_York') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:valid_range) { { since: '2026-10-01', until: '2026-10-07' } }

  describe 'GET /api/v1/accounts/:account_id/analytics' do
    context 'without authentication' do
      it 'refuses' do
        get "/api/v1/accounts/#{account.id}/analytics", params: valid_range
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the caller is an agent' do
      it 'refuses, following the reporting permission the product already has' do
        get "/api/v1/accounts/#{account.id}/analytics",
            params: valid_range, headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the caller administers a different account' do
      it 'refuses, so an account id in the path cannot select another tenant' do
        get "/api/v1/accounts/#{account.id}/analytics",
            params: valid_range, headers: other_administrator.create_new_auth_token
        expect(response).to have_http_status(:unauthorized)
      end

      it 'answers for its own account with its own timezone, never the other one' do
        get "/api/v1/accounts/#{other_account.id}/analytics",
            params: valid_range, headers: other_administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['timezone']['name']).to eq('America/New_York')
      end
    end

    context 'when the caller is an administrator' do
      it 'reports the account timezone and the resolved half-open window' do
        get "/api/v1/accounts/#{account.id}/analytics",
            params: valid_range, headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['timezone']).to include('name' => 'Asia/Kuwait', 'source' => 'account.reporting_timezone')
        expect(body['range']).to include(
          'since' => '2026-10-01', 'until' => '2026-10-07', 'group_by' => 'day',
          'timezone' => 'Asia/Kuwait', 'starts_at' => '2026-09-30T21:00:00Z',
          'ends_at' => '2026-10-07T21:00:00Z', 'boundaries' => 'start inclusive, end exclusive'
        )
      end

      it 'reports the fallback source when the account has no reporting timezone' do
        plain = create(:account)
        plain_admin = create(:user, account: plain, role: :administrator)

        get "/api/v1/accounts/#{plain.id}/analytics",
            params: valid_range, headers: plain_admin.create_new_auth_token

        expect(response.parsed_body['timezone']).to include('name' => 'UTC', 'source' => 'fallback')
      end

      it 'lists every metric family with its filters and rollup-capable metrics' do
        get "/api/v1/accounts/#{account.id}/analytics",
            params: valid_range, headers: administrator.create_new_auth_token

        families = response.parsed_body['families']
        expect(families.keys).to match_array(%w[conversations whatsapp campaigns automations flows commerce tickets])
        expect(families['conversations']['filters']).to match_array(%w[inbox_id channel_type team_id agent_id])
        expect(families['commerce']['filters']).to eq(['provider'])
        expect(families['whatsapp']['rollup_capable_metrics']).to be_empty
      end

      it 'is byte-identical for two administrators of the same account' do
        second_admin = create(:user, account: account, role: :administrator)

        get "/api/v1/accounts/#{account.id}/analytics",
            params: valid_range, headers: administrator.create_new_auth_token
        first = response.body

        get "/api/v1/accounts/#{account.id}/analytics",
            params: valid_range, headers: second_admin.create_new_auth_token

        expect(response.body).to eq(first)
      end

      it 'ignores a client-supplied timezone, so the viewer cannot shift the buckets' do
        get "/api/v1/accounts/#{account.id}/analytics",
            params: valid_range.merge(timezone: 'America/Los_Angeles', timezone_offset: '-7'),
            headers: administrator.create_new_auth_token

        expect(response.parsed_body['timezone']['name']).to eq('Asia/Kuwait')
        expect(response.parsed_body['range']['starts_at']).to eq('2026-09-30T21:00:00Z')
      end
    end

    context 'with an unusable request' do
      def get_meta(params)
        get "/api/v1/accounts/#{account.id}/analytics",
            params: params, headers: administrator.create_new_auth_token
      end

      it 'answers 422 and names the problem for a missing date' do
        get_meta(until: '2026-10-07')
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include('since')
      end

      it 'answers 422 for an epoch timestamp, because the contract is calendar dates' do
        get_meta(since: '1759276800', until: '1759881600')
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include('YYYY-MM-DD')
      end

      it 'answers 422 for an inverted range' do
        get_meta(since: '2026-10-07', until: '2026-10-01')
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'answers 422 for an unsupported group_by' do
        get_meta(valid_range.merge(group_by: 'hour'))
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include('day, week, month')
      end

      it 'answers 422 for a range above the bucket ceiling' do
        get_meta(since: '2024-01-01', until: '2026-10-07')
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include('maximum')
      end

      it 'leaks no internal detail in the error body' do
        get_meta(since: 'nonsense')
        expect(response.parsed_body.keys).to eq(['message'])
      end
    end
  end
end
