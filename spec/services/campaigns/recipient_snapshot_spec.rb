require 'rails_helper'

# The snapshot a one-off WhatsApp campaign leaves behind
# (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md §4.1, §4.4).
#
# A campaign's audience cannot be reconstructed afterwards -- it keeps references to labels and audiences, never
# the conditions -- so the row written as the campaign runs is the only answer to "who did this go to".
RSpec.describe Campaigns::RecipientSnapshot do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:label) { create(:label, account: account, title: 'autumn') }

  # A NAMED template of the channel's own synced list, approved, whose body carries a variable -- so the text
  # recorded per recipient is this contact's text and not one string shared by the run.
  let(:template_params) do
    { 'name' => 'ticket_status_updated', 'namespace' => '23423423_2342423_324234234_2343224', 'category' => 'UTILITY',
      'language' => 'en', 'processed_params' => { 'name' => '{{contact.name}}', 'ticket_id' => 'T-900' } }
  end
  let(:campaign) do
    create(:campaign, account: account, inbox: inbox, audience: [{ type: 'Label', id: label.id }],
                      template_params: template_params)
  end
  let(:snapshot) { described_class.new(campaign) }

  describe 'writing one outcome' do
    let(:contact) { create(:contact, account: account, phone_number: '+96550000001') }

    it 'writes one row per contact, carrying the campaign\'s own account and inbox' do
      second = create(:contact, account: account, phone_number: '+96550000002')

      snapshot.sent(contact, source_id: 'wamid.1', message_content: 'Hello')
      snapshot.skipped(second, described_class::NO_DESTINATION)

      expect(campaign.campaign_recipients.pluck(:contact_id, :status, :account_id, :inbox_id)).to contain_exactly(
        [contact.id, 'sent', account.id, inbox.id], [second.id, 'skipped', account.id, inbox.id]
      )
    end

    it 'leaves a skipped row without a sent_at, because nothing was attempted' do
      snapshot.skipped(contact, described_class::NO_DESTINATION)

      expect(campaign.campaign_recipients.sole).to have_attributes(
        status: 'skipped', sent_at: nil, source_id: nil, failed_at: nil,
        error_message: described_class::NO_DESTINATION
      )
    end

    it 'updates the contact\'s existing row on a re-run rather than failing on the unique index' do
      snapshot.sent(contact, source_id: 'wamid.1', message_content: 'the first text')
      row = campaign.campaign_recipients.sole
      row.record_outcome!(:delivered, reported_at: Time.zone.parse('2026-10-10 09:00:00'))
      created_at = row.reload.created_at

      snapshot.sent(contact, source_id: 'wamid.2', message_content: 'the second text')

      expect(campaign.campaign_recipients.count).to eq(1)
      # A re-run sends a NEW message under a new identifier, so the previous message's delivery and read times
      # are no longer about anything; leaving them would have the analytics count a delivery that has not
      # happened yet. `created_at` is the one column a re-run must not move, or the row leaves the window the
      # analytics already counted it in.
      expect(row.reload).to have_attributes(status: 'sent', source_id: 'wamid.2', message_content: 'the second text',
                                            delivered_at: nil, read_at: nil, failed_at: nil, created_at: created_at)
    end
  end

  describe 'the send path' do
    before do
      account.enable_features!(:whatsapp_campaign)
      allow(channel).to receive(:send_template) { |to, _template_info, _message| "wamid.#{to}" }
      # The campaign's inbox hands back a freshly loaded channel, so the stubbed instance has to be injected.
      allow_any_instance_of(Whatsapp::OneoffCampaignService).to receive(:channel).and_return(channel) # rubocop:disable RSpec/AnyInstance
    end

    it 'records every sendable contact as handed to Meta, with its own identifier and the text it was sent' do
      contacts = Array.new(3) { |index| create(:contact, account: account, name: "Nour #{index}", phone_number: "+9655000001#{index}") }
      contacts.each { |contact| contact.update_labels([label.title]) }

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      rows = campaign.campaign_recipients.to_a
      expect(rows.map(&:status).uniq).to eq(['sent'])
      expect(rows.map(&:sent_at)).to all(be_present)
      expect(rows.map(&:source_id).uniq.length).to eq(3)
      # The template's variables resolve against the contact, so the body differs per recipient -- which is why
      # the text has to be stored per row and cannot be recomputed from the campaign later.
      expect(rows.map(&:message_content)).to match_array(
        contacts.map { |contact| "Hello #{contact.name},  Your support ticket with ID: #T-900 has been updated by the support agent." }
      )
      expect(Campaigns::RecipientMetrics.new(campaign).as_json).to include('audience' => 3, 'sent' => 3)
      expect(campaign.reload).to be_completed
    end

    it 'skips a contact with no phone number and no business-scoped id, and sends to the rest' do
      sendable = Array.new(2) { |index| create(:contact, account: account, phone_number: "+9655000002#{index}") }
      unreachable = create(:contact, account: account, name: 'Unreachable', phone_number: nil)
      (sendable + [unreachable]).each { |contact| contact.update_labels([label.title]) }

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(campaign.campaign_recipients.pluck(:contact_id, :status, :error_message)).to contain_exactly(
        [sendable.first.id, 'sent', nil], [sendable.second.id, 'sent', nil],
        [unreachable.id, 'skipped', described_class::NO_DESTINATION]
      )
      expect(campaign.campaign_recipients.skipped.sole.sent_at).to be_nil
      # Skipped and failed are different problems with different remedies -- fix your data versus fix your
      # template -- so a contact Lynomia refused must never be counted as a provider rejection.
      expect(Campaigns::RecipientMetrics.new(campaign).as_json).to include('skipped' => 1, 'failed' => 0, 'sent' => 2)
    end

    it 'writes one row for a contact that two of the campaign\'s labels both contain' do
      spring = create(:label, account: account, title: 'spring')
      campaign.update!(audience: [{ type: 'Label', id: label.id }, { type: 'Label', id: spring.id }])
      contact = create(:contact, account: account, phone_number: '+96550000031')
      contact.update_labels([label.title, spring.title])

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(campaign.campaign_recipients.pluck(:contact_id)).to eq([contact.id])
    end

    it 'records a provider rejection and carries on with the rest of the audience' do
      contacts = Array.new(5) { |index| create(:contact, account: account, phone_number: "+9655000004#{index}") }
      contacts.each { |contact| contact.update_labels([label.title]) }
      rejected = contacts.second
      allow(channel).to receive(:send_template) { |to, _template_info, _message| to == rejected.phone_number ? nil : "wamid.#{to}" }
      allow(channel).to receive(:last_send_failure).and_return(
        Whatsapp::SendFailure.new(code: '131026', title: 'Message undeliverable', message: 'Receiver cannot receive messages')
      )

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      # One unsendable contact must not abort the other four: the row count is the point, not the states.
      expect(campaign.campaign_recipients.group(:status).count).to eq('sent' => 4, 'failed' => 1)
      expect(campaign.campaign_recipients.failed.sole).to have_attributes(
        contact_id: rejected.id, error_code: '131026', error_title: 'Message undeliverable', source_id: nil
      )
      expect(campaign.campaign_recipients.failed.sole.failed_at).to be_present
      expect(campaign.reload).to be_completed
    end

    it 'tells its skip reasons apart and keeps contact data out of every one of them' do
      unreachable = create(:contact, account: account, name: 'Latifa Alqattan', phone_number: nil)
      ambiguous = create(:contact, account: account, name: 'Omar Alfahad', phone_number: nil)
      2.times { |index| create(:contact_inbox, contact: ambiguous, inbox: inbox, source_id: "KW.ENT.BSUID#{index}") }
      nameless = create(:contact, account: account, name: '', phone_number: '+96550000051')
      [unreachable, ambiguous, nameless].each { |contact| contact.update_labels([label.title]) }

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      reasons = campaign.campaign_recipients.skipped.pluck(:contact_id, :error_message).to_h
      expect(reasons).to eq(unreachable.id => described_class::NO_DESTINATION,
                            ambiguous.id => described_class::AMBIGUOUS_DESTINATION,
                            nameless.id => described_class::BLANK_TEMPLATE_VARIABLES)
      expect(described_class::SKIP_REASONS).to include(*reasons.values)
      # The analytics group the skip breakdown on this column directly, so a reason carrying a name or a number
      # would both explode that breakdown's cardinality and put a recipient's own data into an analytics
      # response.
      personal = [unreachable.name, ambiguous.name, nameless.phone_number]
      expect(reasons.values.select { |reason| personal.any? { |value| reason.include?(value) } }).to be_empty
    end

    it 'skips the whole audience with one fixed reason when the campaign has no template parameters' do
      campaign.update!(template_params: {})
      contact = create(:contact, account: account, phone_number: '+96550000061')
      contact.update_labels([label.title])

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(campaign.campaign_recipients.sole).to have_attributes(
        status: 'skipped', sent_at: nil, error_message: described_class::NO_TEMPLATE_PARAMS
      )
      expect(channel).not_to have_received(:send_template)
    end
  end
end
