require 'rails_helper'

# The forward-only ladder a provider report walks a recipient along
# (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md §4.2, §4.3).
#
# Meta reports `sent`, `delivered`, `read` and `failed` asynchronously, out of order and more than once, so the
# interesting property is not that a report is applied but that no report can ever lose ground already made.
RSpec.describe CampaignRecipient do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox) }
  let(:contact) { create(:contact, account: account, phone_number: '+96550000001') }

  # Fixed instants rather than relative ones: several assertions below turn on a timestamp keeping the value it
  # was first written with, which only means something against a value the example chose.
  let(:sent_at) { Time.zone.parse('2026-10-10 09:00:00') }
  let(:delivered_report_at) { Time.zone.parse('2026-10-10 09:01:00') }
  let(:read_report_at) { Time.zone.parse('2026-10-10 09:02:00') }
  let(:failure_report_at) { Time.zone.parse('2026-10-10 09:03:00') }

  let(:recipient) do
    described_class.create!(account: account, campaign: campaign, inbox: inbox, contact: contact,
                            status: :sent, source_id: 'wamid.1', sent_at: sent_at)
  end

  describe '#record_outcome!' do
    it 'advances a sent recipient to delivered and leaves the send untouched' do
      expect(recipient.record_outcome!(:delivered, reported_at: delivered_report_at)).to be(true)

      expect(recipient.reload).to have_attributes(status: 'delivered', delivered_at: delivered_report_at,
                                                  sent_at: sent_at, source_id: 'wamid.1')
      expect(Campaigns::RecipientMetrics.new(campaign).as_json).to include('delivered' => 1, 'read' => 0)
    end

    it 'ends a recipient read before any delivered report at read, with delivered_at still null' do
      expect(recipient.record_outcome!(:read, reported_at: read_report_at)).to be(true)

      expect(recipient.reload).to have_attributes(status: 'read', read_at: read_report_at, delivered_at: nil)
      # Delivery is counted as `delivered_at IS NOT NULL OR read_at IS NOT NULL`, so this recipient is already
      # delivered as far as every count is concerned -- a message that was read reached the device.
      expect(Campaigns::RecipientMetrics.new(campaign).as_json).to include('delivered' => 1, 'read' => 1)
    end

    it 'backfills delivered_at from a late delivered report without demoting a read recipient' do
      recipient.record_outcome!(:read, reported_at: read_report_at)

      expect(recipient.record_outcome!(:delivered, reported_at: delivered_report_at)).to be(true)

      expect(recipient.reload).to have_attributes(status: 'read', read_at: read_report_at,
                                                  delivered_at: delivered_report_at)
      # Both timestamps are now set, and the recipient must still be counted once rather than twice.
      expect(Campaigns::RecipientMetrics.new(campaign).as_json).to include('delivered' => 1, 'read' => 1)
    end

    it 'writes nothing at all when the same delivered report is redelivered' do
      recipient.record_outcome!(:delivered, reported_at: delivered_report_at)
      unchanged = recipient.reload.attributes

      # A second report carrying a LATER instant, so a re-stamp would show up as a different value rather than
      # as the same one written twice.
      expect(recipient.record_outcome!(:delivered, reported_at: read_report_at)).to be(false)

      # `attributes` covers updated_at too: a redelivered webhook must not even touch the row.
      expect(recipient.reload.attributes).to eq(unchanged)
    end

    it 'drops a failure reported over a delivery, failed_at included' do
      recipient.record_outcome!(:delivered, reported_at: delivered_report_at)
      unchanged = recipient.reload.attributes

      expect(recipient.record_outcome!(:failed, reported_at: failure_report_at, error_code: '131026',
                                                error_title: 'Message undeliverable')).to be(false)

      expect(recipient.reload.attributes).to eq(unchanged)
      # The analytics count failures from this column alone, so stamping it "for the record" over a delivery
      # would make the failure count permanently wrong rather than merely untidy.
      expect(recipient.failed_at).to be_nil
      expect(Campaigns::RecipientMetrics.new(campaign).as_json).to include('delivered' => 1, 'failed' => 0)
    end

    it 'drops a failure reported over a read recipient as well' do
      recipient.record_outcome!(:read, reported_at: read_report_at)
      unchanged = recipient.reload.attributes

      expect(recipient.record_outcome!(:failed, reported_at: failure_report_at, error_code: '131026')).to be(false)

      expect(recipient.reload.attributes).to eq(unchanged)
      expect(recipient.failed_at).to be_nil
      expect(Campaigns::RecipientMetrics.new(campaign).as_json).to include('delivered' => 1, 'failed' => 0)
    end

    it 'records a failure reported over a sent recipient with the provider\'s code, title and reason' do
      expect(recipient.record_outcome!(:failed, reported_at: failure_report_at, error_code: '131047',
                                                error_title: 'Re-engagement message',
                                                error_message: 'More than 24 hours have passed')).to be(true)

      expect(recipient.reload).to have_attributes(
        status: 'failed', failed_at: failure_report_at, error_code: '131047',
        error_title: 'Re-engagement message', error_message: 'More than 24 hours have passed'
      )
      expect(Campaigns::RecipientMetrics.new(campaign).as_json).to include('failed' => 1, 'delivered' => 0)
    end

    it 'records a failure reported over a queued recipient, which Meta never accepted at all' do
      queued = described_class.create!(account: account, campaign: campaign, inbox: inbox,
                                       contact: create(:contact, account: account))

      expect(queued.record_outcome!(:failed, reported_at: failure_report_at, error_code: '131026')).to be(true)

      expect(queued.reload).to have_attributes(status: 'failed', failed_at: failure_report_at,
                                               error_code: '131026', source_id: nil, sent_at: nil)
    end

    it 'refuses a reported state that is not a provider event' do
      # `queued` and `skipped` are Lynomia's own states: nothing Meta can say puts a recipient into either, and a
      # value the provider path never produces must not be allowed to write anything.
      %w[queued skipped bounced].each do |state|
        expect(recipient.record_outcome!(state)).to be(false)
      end

      expect(recipient.reload).to have_attributes(status: 'sent', delivered_at: nil, read_at: nil, failed_at: nil)
    end
  end

  describe 'one row per contact per campaign' do
    it 'refuses a second row for a contact the campaign already addressed' do
      recipient

      duplicate = described_class.new(account: account, campaign: campaign, inbox: inbox, contact: contact,
                                      status: :sent, source_id: 'wamid.2')

      expect { duplicate.save! }.to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::RecordNotUnique') })
    end
  end
end
