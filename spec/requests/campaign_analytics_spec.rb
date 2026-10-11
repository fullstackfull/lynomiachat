require 'rails_helper'

# The two read endpoints an operator judges a finished campaign by
# (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md §2).
#
# A file-scope local rather than a constant: the fixture below closes over it at definition time and nothing is
# added to Object. Sixty recipients across the whole state vocabulary in KNOWN quantities, so every counter can
# be checked against a number the example chose instead of against another query of the same table.
state_mix = { queued: 10, sent: 10, delivered: 12, read: 8, failed: 11, skipped: 9 }.freeze

RSpec.describe 'Campaign recipient analytics', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox) }
  let(:metrics_path) { "/api/v1/accounts/#{account.id}/campaigns/#{campaign.id}/analytics/metrics" }
  let(:contacts_path) { "/api/v1/accounts/#{account.id}/campaigns/#{campaign.id}/analytics/contacts" }
  let(:message_body) { 'Your parcel PARCEL-SECRET-7 is out for delivery' }

  # A mirrored second tenant: the same shape of data under another account, so a missing account predicate shows
  # up as that account's recipient appearing rather than as nothing at all.
  let(:other) do
    other_account = create(:account)
    other_inbox = create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud', sync_templates: false,
                                            validate_provider_config: false).inbox
    other_contact = create(:contact, account: other_account, name: 'Almutairi Theirs', phone_number: '+96599999999')
    other_campaign = create(:campaign, account: other_account, inbox: other_inbox)
    CampaignRecipient.create!(account: other_account, campaign: other_campaign, inbox: other_inbox,
                              contact: other_contact, status: :sent, source_id: 'wamid.theirs',
                              sent_at: 1.hour.ago, message_content: 'Their own parcel is on its way')
    { campaign: other_campaign, contact: other_contact }
  end

  let!(:recipients) do
    position = 0
    state_mix.flat_map do |state, count|
      Array.new(count) do
        position += 1
        CampaignRecipient.create!(
          account: account, campaign: campaign, inbox: inbox, status: state,
          contact: create(:contact, account: account, name: "Alqattan #{position}", phone_number: format('+9655%06d', position)),
          **outcome(state, position)
        )
      end
    end
  end

  # What each state's row has to carry for the counters to be readable off it. A `read` row deliberately has NO
  # delivered_at: Meta reports read before delivered often enough that the delivered count has to cover it, and
  # a fixture where every read row also has a delivered_at would never show that.
  def outcome(state, position)
    case state
    when :queued then {}
    when :sent then { source_id: "wamid.sent.#{position}", sent_at: 2.hours.ago, message_content: message_body }
    when :delivered
      { source_id: "wamid.delivered.#{position}", sent_at: 2.hours.ago, delivered_at: 1.hour.ago, message_content: message_body }
    when :read then { source_id: "wamid.read.#{position}", sent_at: 2.hours.ago, read_at: 1.hour.ago, message_content: message_body }
    when :failed
      { failed_at: 1.hour.ago, error_code: '131026', error_title: 'Message undeliverable', message_content: message_body }
    when :skipped then { error_message: Campaigns::RecipientSnapshot::NO_DESTINATION }
    end
  end

  describe 'GET analytics/contacts' do
    it 'serves 25 rows a page and reports the whole snapshot as the total' do
      get contacts_path, params: { page: 2 }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].length).to eq(25)
      # The pager is driven by the total, not by the page, and is shown only when the total exceeds one page.
      expect(response.parsed_body['meta']['total_count']).to eq(60)
    end

    it 'serves the remainder on the last page' do
      get contacts_path, params: { page: 3 }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].length).to eq(10)
      expect(response.parsed_body['meta']['total_count']).to eq(60)
    end

    it 'reports the failed count rather than the whole snapshot once the list is filtered' do
      get contacts_path, params: { status: 'failed' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('status').uniq).to eq(['failed'])
      expect(response.parsed_body['meta']['total_count']).to eq(state_mix[:failed])
      # The reason column reads error_message -> error_title -> error_code, so a failed row has to arrive with at
      # least one of the three for the operator to have anything to act on.
      expect(response.parsed_body['payload']).to all(include('error_code' => '131026', 'error_title' => 'Message undeliverable'))
    end

    it 'carries every key the recipient table reads on every row' do
      get contacts_path, headers: admin.create_new_auth_token, as: :json
      rows = response.parsed_body['payload']

      expect(rows.length).to eq(25)
      expect(rows).to all(include('contact', 'status', 'message_content', 'error_code', 'error_title', 'error_message'))
      # `contact.id` is the row key and the link target, so a row returned without it cannot be rendered at all.
      expect(rows.map { |row| row['contact'] }).to all(include('id', 'name', 'phone_number'))
      expect(rows.map { |row| row.dig('contact', 'id') }).to all(be_present)
    end

    it 'refuses an unknown status at the request boundary instead of letting it reach the database' do
      statements = []

      ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql] }, 'sql.active_record') do
        get contacts_path, params: { status: 'bounced' }, headers: admin.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('bounced')
      # An unknown state reaching the enum cast raises, which would reach the exception tracker as a 500 for what
      # is no more than a typo in a query string.
      expect(statements.grep(/campaign_recipients/)).to be_empty
    end

    it 'still renders the list after one of the recipients\' contacts is deleted' do
      recipients.first.contact.destroy!

      get contacts_path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']['total_count']).to eq(59)
      expect(response.parsed_body['payload'].map { |row| row.dig('contact', 'id') }).to all(be_present)
    end
  end

  describe 'GET analytics/metrics' do
    it 'reports six counters that agree with status_counts' do
      get metrics_path, headers: admin.create_new_auth_token, as: :json
      body = response.parsed_body

      expect(body['status_counts']).to eq(state_mix.transform_keys(&:to_s))
      expect(body['audience']).to eq(body['status_counts'].values.sum)
      # `delivered` has to include everything that was read: the breakdown chart draws its delivered band as
      # `delivered - read`, so a read recipient missing from delivered would clamp that band to zero and show a
      # campaign that was read but never delivered.
      expect(body['delivered']).to eq(body['status_counts']['delivered'] + body['status_counts']['read'])
      # `sent` is "Meta accepted it", which every recipient since delivered or read also was.
      expect(body['sent']).to eq(%w[sent delivered read].sum { |state| body['status_counts'][state] })
      expect(body).to include('read' => body['status_counts']['read'], 'failed' => body['status_counts']['failed'],
                              'skipped' => body['status_counts']['skipped'])
    end

    it 'reports a per-state count that matches the rows the filtered list returns for that state' do
      get metrics_path, headers: admin.create_new_auth_token, as: :json

      response.parsed_body['status_counts'].each do |state, count|
        get contacts_path, params: { status: state }, headers: admin.create_new_auth_token, as: :json

        expect(response.parsed_body['meta']['total_count']).to eq(count), "#{state} disagreed with the list"
        expect(response.parsed_body['payload'].pluck('status').uniq - [state]).to be_empty
      end
    end

    it 'reports a positive queued and sent count while the campaign is still being reported on' do
      get metrics_path, headers: admin.create_new_auth_token, as: :json

      # The page words its "still processing" banner off exactly these two numbers.
      expect(response.parsed_body['status_counts']['queued']).to be_positive
      expect(response.parsed_body['status_counts']['sent']).to be_positive
    end
  end

  describe '[isolation] another account\'s campaign' do
    it 'answers 404 at both endpoints and returns none of its recipients' do
      %w[metrics contacts].each do |endpoint|
        get "/api/v1/accounts/#{account.id}/campaigns/#{other[:campaign].id}/analytics/#{endpoint}",
            headers: admin.create_new_auth_token, as: :json

        # Campaign ids are sequential and guessable, so the lookup happens inside the requesting account and an
        # id from elsewhere is simply not found.
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include(other[:contact].name)
        expect(response.body).not_to include(other[:contact].phone_number)
      end
    end
  end

  describe 'the account-wide campaign analytics' do
    it 'carries no contact name, phone number or message body in its failure and skip breakdowns' do
      metrics = Analytics::Campaigns::Metrics.new(
        account: account,
        date_range: Analytics::DateRange.new(account: account, since: 6.days.ago.to_date.to_s, until_value: Date.current.to_s),
        filters: Analytics::FilterSet.new(account: account, family: :campaigns, params: {})
      )

      # The groupings are a provider error code and one of the fixed skip reasons -- values with no recipient in
      # them at all, which is what keeps the breakdown low cardinality as well as safe to return.
      expect(metrics.breakdown(:failure)).to contain_exactly(hash_including(label: '131026', value: state_mix[:failed]))
      expect(metrics.breakdown(:skip_reason)).to contain_exactly(
        hash_including(label: Campaigns::RecipientSnapshot::NO_DESTINATION, value: state_mix[:skipped])
      )

      serialized = (metrics.breakdown(:failure) + metrics.breakdown(:skip_reason)).to_json
      customer_data = recipients.flat_map { |row| [row.contact.name, row.contact.phone_number] }.push(message_body)
      expect(customer_data.select { |value| serialized.include?(value) }).to be_empty
    end
  end
end
