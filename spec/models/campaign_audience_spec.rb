require 'rails_helper'

# Shared audiences as campaign recipients (docs/campaigns/02-recipients.md).
RSpec.describe Campaign do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:sms_inbox) { create(:inbox, account: account, channel: create(:channel_sms, account: account)) }
  let(:label) { create(:label, account: account) }
  let(:vip_query) { { 'payload' => [{ 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['vip.example'] }] } }
  let(:vips) { create(:custom_filter, account: account, user: admin, filter_type: :contact, shared: true, name: 'VIP', query: vip_query) }
  let(:gulf) do
    create(:custom_filter, account: account, user: admin, filter_type: :contact, shared: true, name: 'Gulf',
                           query: { 'payload' => [{ 'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['sa'] }] })
  end
  let!(:vip) do
    create(:contact, account: account, email: 'layla@vip.example', phone_number: '+966500000001', additional_attributes: { 'country_code' => 'SA' })
  end
  let!(:tagged) { create(:contact, account: account, email: 'omar@mail.example', phone_number: '+966500000002') }
  let!(:other) { create(:contact, account: account, email: 'sara@mail.example', phone_number: '+966500000003') }

  before { tagged.update_labels([label.title]) }

  describe 'validation' do
    it 'accepts the shared contact audiences of the account beside labels' do
      campaign = build(:campaign, account: account, inbox: sms_inbox,
                                  audience: [{ type: 'Label', id: label.id }, { type: 'Audience', id: vips.id }])

      expect(campaign).to be_valid
    end

    it 'refuses personal audiences, audiences of another account, ids that are not integers and live chat campaigns' do
      personal = create(:custom_filter, account: account, user: admin, filter_type: :contact, name: 'Mine', query: vip_query)
      foreign = create(:custom_filter, account: create(:account), user: nil, filter_type: :contact, shared: true, name: 'Theirs', query: vip_query)
      website = create(:inbox, account: account)

      [[sms_inbox, personal.id], [sms_inbox, foreign.id], [sms_inbox, vips.id.to_s], [website, vips.id]].each do |inbox, id|
        campaign = build(:campaign, account: account, inbox: inbox, audience: [{ type: 'Audience', id: id }])

        expect(campaign).not_to be_valid
        expect(campaign.errors.full_messages).to include(I18n.t('errors.campaigns.audience_not_shared'))
      end
    end

    it 'leaves label entries as they were: never validated' do
      campaign = build(:campaign, account: account, inbox: sms_inbox, audience: [{ type: 'Label', id: 0 }])

      expect(campaign).to be_valid
    end
  end

  describe '#audience_contacts' do
    it 'is the label relation when the campaign lists labels only' do
      campaign = create(:campaign, account: account, inbox: sms_inbox, audience: [{ type: 'Label', id: label.id }])

      expect(campaign.audience_contacts.to_sql).to eq(account.contacts.tagged_with([label.title], any: true).to_sql)
      expect(campaign.audience_contacts).to contain_exactly(tagged)
    end

    it 'is the union of labels and audiences, each contact once' do
      tagged.update!(email: 'omar@vip.example')
      campaign = create(:campaign, account: account, inbox: sms_inbox,
                                   audience: [{ type: 'Label', id: label.id }, { type: 'Audience', id: vips.id }, { type: 'Audience', id: gulf.id }])

      expect(campaign.audience_contacts.to_a).to contain_exactly(vip, tagged)
      expect(campaign.audience_contacts.count).to eq(2)
    end

    it 'resolves audiences when asked, not when the campaign was created' do
      campaign = create(:campaign, account: account, inbox: sms_inbox, audience: [{ type: 'Audience', id: vips.id }])
      newcomer = create(:contact, account: account, email: 'noor@vip.example')
      vips.update!(query: { 'payload' => [{ 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['noor'] }] })

      expect(campaign.audience_contacts).to contain_exactly(newcomer)
      expect(campaign.reload.audience).to eq([{ 'type' => 'Audience', 'id' => vips.id }])
    end

    it 'never reaches another account\'s contacts' do
      create(:contact, account: create(:account), email: 'twin@vip.example')
      campaign = create(:campaign, account: account, inbox: sms_inbox, audience: [{ type: 'Audience', id: vips.id }])

      expect(campaign.audience_contacts).to contain_exactly(vip)
    end

    it 'fails before anything is sent when a referenced audience is no longer shared' do
      campaign = create(:campaign, account: account, inbox: sms_inbox, audience: [{ type: 'Audience', id: vips.id }])
      vips.update_columns(shared: false) # rubocop:disable Rails/SkipsModelValidations

      expect { campaign.audience_contacts }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context 'with Commerce conditions' do
      include_context 'with commerce encryption'

      it 'reads them from the local summaries and calls no store' do
        account.enable_features!('lynomia_commerce')
        link = create(:commerce_customer_link, store: create(:commerce_store, account: account), contact: other)
        Commerce::ContactMetric.create!(account: account, customer_link: link, orders_count: 2, active_orders_count: 0, spend: { 'SAR' => '900.00' },
                                        order_statuses: %w[completed], fetched_at: Time.current)
        buyers = create(:custom_filter, account: account, user: admin, filter_type: :contact, shared: true, name: 'Buyers',
                                        query: { 'payload' => [{ 'attribute_key' => 'commerce_orders_count', 'filter_operator' => 'is_greater_than',
                                                                 'values' => ['1'] }] })
        campaign = create(:campaign, account: account, inbox: sms_inbox, audience: [{ type: 'Audience', id: buyers.id }])

        expect(campaign.audience_contacts).to contain_exactly(other)
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end
  end

  describe 'sending' do
    it 'sends an SMS campaign once to each contact of its labels and audiences' do
      tagged.update!(email: 'omar@vip.example')
      campaign = create(:campaign, account: account, inbox: sms_inbox,
                                   audience: [{ type: 'Label', id: label.id }, { type: 'Audience', id: vips.id }])
      channel = campaign.inbox.channel
      allow(channel).to receive(:send_text_message)
      allow_any_instance_of(Sms::OneoffSmsCampaignService).to receive(:channel).and_return(channel) # rubocop:disable RSpec/AnyInstance

      Sms::OneoffSmsCampaignService.new(campaign: campaign).perform

      expect(channel).to have_received(:send_text_message).twice
      expect(channel).to have_received(:send_text_message).with(vip.phone_number, anything).once
      expect(channel).to have_received(:send_text_message).with(tagged.phone_number, anything).once
      expect(campaign.reload).to be_completed
    end

    # The template name has to be one the channel's synced list actually holds and WhatsApp has approved: since the
    # processor resolves the name from the template it finds, a campaign naming a template the inbox does not have
    # now skips every recipient instead of handing the send to Meta (app/services/whatsapp/template_processor_service.rb).
    it 'records and sends a WhatsApp campaign once to each contact of its labels and audiences' do
      account.enable_features!(:whatsapp_campaign)
      tagged.update!(email: 'omar@vip.example')
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      campaign = create(:campaign, account: account, inbox: channel.inbox,
                                   audience: [{ type: 'Label', id: label.id }, { type: 'Audience', id: vips.id }],
                                   template_params: { 'name' => 'test_no_params_template', 'namespace' => 'ns', 'category' => 'UTILITY',
                                                      'language' => 'en', 'processed_params' => {} })
      allow(channel).to receive(:send_template).and_return('wamid.1', 'wamid.2')
      allow_any_instance_of(Whatsapp::OneoffCampaignService).to receive(:channel).and_return(channel) # rubocop:disable RSpec/AnyInstance

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(channel).to have_received(:send_template).twice
      expect(campaign.campaign_recipients.pluck(:contact_id, :status)).to contain_exactly([vip.id, 'sent'], [tagged.id, 'sent'])
    end
  end
end
