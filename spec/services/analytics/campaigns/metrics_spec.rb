require 'rails_helper'

RSpec.describe Analytics::Campaigns::Metrics do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago) }
  let(:label) { create(:label, account: account, title: 'vip') }
  let(:audience) { create(:custom_filter, account: account, name: 'Repeat buyers', filter_type: :contact, shared: true) }

  let(:date_range) do
    Analytics::DateRange.new(account: account, since: '2026-10-01', until_value: '2026-10-07', group_by: 'day')
  end

  def metrics(filters: {})
    described_class.new(
      account: account, date_range: date_range,
      filters: Analytics::FilterSet.new(account: account, family: :campaigns, params: filters)
    )
  end

  def recipient(at: Time.utc(2026, 10, 2, 10, 0), for_campaign: nil, for_inbox: nil, for_account: account, **attributes)
    CampaignRecipient.create!(
      account: for_account, campaign: for_campaign || campaign, inbox: for_inbox || inbox,
      contact: create(:contact, account: for_account), created_at: at, **attributes
    )
  end

  describe 'recipients_targeted' do
    it 'counts recipients created inside the account-timezone window' do
      recipient
      # 22:00 UTC on 30 September is 1 October in Kuwait, so it belongs to this range.
      recipient(at: Time.utc(2026, 9, 30, 22, 0))
      # 20:00 UTC on 30 September is still 30 September locally, so it does not.
      recipient(at: Time.utc(2026, 9, 30, 20, 0))

      expect(metrics.recipients_targeted).to eq(2)
    end

    it "never counts another account's recipients" do
      other_campaign = create(:campaign, account: other_account, campaign_type: :one_off, scheduled_at: 1.hour.ago)
      recipient(for_account: other_account, for_campaign: other_campaign, for_inbox: other_campaign.inbox)

      expect(metrics.recipients_targeted).to eq(0)
    end
  end

  describe 'campaigns_run' do
    it 'counts the distinct campaigns that addressed anyone in the period' do
      second = create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
      recipient
      recipient
      recipient(for_campaign: second)

      expect(metrics.campaigns_run).to eq(2)
    end
  end

  describe 'funnel states' do
    it 'counts a send only once Meta returned a message id' do
      recipient(status: :sent, source_id: 'wamid.1', sent_at: Time.utc(2026, 10, 2, 10, 1))
      recipient(status: :queued)

      expect(metrics.sent).to eq(1)
    end

    it 'counts a recipient read before any delivered event as delivered' do
      recipient(status: :read, source_id: 'wamid.2', read_at: Time.utc(2026, 10, 2, 11, 0))

      expect(metrics.delivered).to eq(1)
      expect(metrics.read).to eq(1)
    end

    it 'counts a delivered recipient as delivered but not read' do
      recipient(status: :delivered, source_id: 'wamid.3', delivered_at: Time.utc(2026, 10, 2, 11, 0))

      expect(metrics.delivered).to eq(1)
      expect(metrics.read).to eq(0)
    end

    it 'counts failed, skipped and pending separately' do
      recipient(status: :failed, failed_at: Time.utc(2026, 10, 2, 11, 0), error_code: '131049')
      recipient(status: :skipped, error_message: 'Contact has no phone number')
      recipient(status: :queued)

      expect(metrics.failed).to eq(1)
      expect(metrics.skipped).to eq(1)
      expect(metrics.pending).to eq(1)
    end

    it 'agrees with the status ladder on a recipient the real writer advanced' do
      row = recipient(status: :sent, source_id: 'wamid.4', sent_at: Time.utc(2026, 10, 2, 10, 1))
      row.update_from_whatsapp_status!(status: 'read', timestamp: Time.utc(2026, 10, 2, 11, 0).to_i)
      row.update_from_whatsapp_status!(status: 'delivered', timestamp: Time.utc(2026, 10, 2, 10, 30).to_i)

      expect(row.reload.status).to eq('read')
      expect(row.delivered_at).to be_present
      expect(metrics.delivered).to eq(1)
      expect(metrics.read).to eq(1)
    end
  end

  describe 'rates' do
    it 'reports each outcome as a percentage of the recipients targeted' do
      recipient(status: :delivered, source_id: 'wamid.5', delivered_at: Time.utc(2026, 10, 2, 11, 0))
      recipient(status: :read, source_id: 'wamid.6', delivered_at: Time.utc(2026, 10, 2, 11, 0),
                read_at: Time.utc(2026, 10, 2, 12, 0))
      recipient(status: :failed, failed_at: Time.utc(2026, 10, 2, 11, 0))
      recipient(status: :queued)

      expect(metrics.delivery_rate).to eq(50.0)
      expect(metrics.read_rate).to eq(25.0)
      expect(metrics.failure_rate).to eq(25.0)
    end

    it 'returns nil rather than zero when nothing was targeted' do
      expect(metrics.delivery_rate).to be_nil
    end
  end

  describe 'filters' do
    it 'narrows to one campaign' do
      second = create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
      recipient
      recipient(for_campaign: second)

      expect(metrics(filters: { 'campaign_id' => campaign.id }).recipients_targeted).to eq(1)
    end

    it 'narrows to one inbox' do
      recipient
      recipient(for_inbox: other_inbox)

      expect(metrics(filters: { 'inbox_id' => inbox.id }).recipients_targeted).to eq(1)
    end

    it 'refuses a campaign id from another account' do
      foreign = create(:campaign, account: other_account, campaign_type: :one_off, scheduled_at: 1.hour.ago)

      expect { metrics(filters: { 'campaign_id' => foreign.id }) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::UnknownFilterValue') })
    end
  end

  describe 'series' do
    it 'emits one point per bucket including the zeros' do
      recipient(at: Time.utc(2026, 10, 1, 10, 0))
      points = metrics.series(:recipients_targeted)

      expect(points.length).to eq(7)
      expect(points.first).to eq(bucket: '2026-10-01', value: 1)
    end

    it 'buckets by the account timezone, not naive UTC' do
      recipient(at: Time.utc(2026, 10, 1, 22, 0))
      points = metrics.series(:recipients_targeted)

      expect(points.find { |point| point[:bucket] == '2026-10-02' }[:value]).to eq(1)
    end
  end

  describe 'breakdowns' do
    it 'groups recipients by campaign, labelled with the campaign title' do
      recipient
      rows = metrics.breakdown(:campaign)

      expect(rows).to eq([{ id: campaign.id, label: campaign.title, value: 1 }])
    end

    it "groups failures by Meta's error code" do
      recipient(status: :failed, failed_at: Time.utc(2026, 10, 2, 11, 0), error_code: '131049')
      recipient(status: :failed, failed_at: Time.utc(2026, 10, 2, 11, 0), error_code: '131049')
      recipient(status: :failed, failed_at: Time.utc(2026, 10, 2, 11, 0), error_code: '131042')

      expect(metrics.breakdown(:failure).first).to eq(id: '131049', label: '131049', value: 2)
    end

    it 'groups skips by the reason Lynomia recorded' do
      recipient(status: :skipped, error_message: 'Contact has no phone number')
      recipient(status: :skipped, error_message: 'Template parameters are missing')

      rows = metrics.breakdown(:skip_reason)

      expect(rows.map { |row| row[:label] })
        .to contain_exactly('Contact has no phone number', 'Template parameters are missing')
    end

    it 'counts campaigns per targeted audience and label, never recipients' do
      campaign.update!(audience: [{ 'type' => 'Label', 'id' => label.id },
                                  { 'type' => 'Audience', 'id' => audience.id }])
      recipient
      recipient

      rows = metrics.breakdown(:audience)

      expect(rows).to contain_exactly(
        { id: "label:#{label.id}", label: 'vip', value: 1 },
        { id: "audience:#{audience.id}", label: 'Repeat buyers', value: 1 }
      )
    end

    it 'leaves the audience breakdown empty when a campaign recorded no audience reference' do
      recipient
      expect(metrics.breakdown(:audience)).to eq([])
    end
  end
end
