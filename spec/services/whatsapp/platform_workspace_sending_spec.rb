require 'rails_helper'

# P6E. WHAT THE INSTALLATION'S OWN WORKSPACE MAY SEND.
#
# Store Syria's platform workspace exists to tell merchants about their accounts --
# onboarding, a broken integration, a security notice. Essential operational communication
# was authorised; promotional campaigns, feature marketing and bulk announcements explicitly
# were not.
#
# Two things are enforced on the way out, and both are on the conversation path because that
# is what a one-recipient notice actually travels through. The campaign path cannot address a
# named contact at all -- its audience is labels and saved audiences -- so the meter that
# lives there would never have been reached.
RSpec.describe 'sending from the platform workspace', type: :model do
  include_context 'with commerce encryption'

  let(:plan) do
    create(:billing_plan, name: 'Platform operations', active: false, stripe_price_id: nil,
                          limits: { 'campaign_sends' => 2 })
  end
  let(:partner_app) { create(:platform_app, name: 'Store Syria') }
  let(:account) { Billing::PlatformWorkspace.provision!(name: 'Platform', plan: plan, platform_app: partner_app) }
  let(:templates) do
    [{ 'name' => 'integration_broken', 'language' => 'en_US', 'status' => 'approved', 'category' => 'UTILITY',
       'components' => [{ 'type' => 'BODY', 'text' => 'Your integration needs attention.' }] },
     { 'name' => 'new_feature', 'language' => 'en_US', 'status' => 'approved', 'category' => 'MARKETING',
       'components' => [{ 'type' => 'BODY', 'text' => 'Look what we built!' }] }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: templates)
  end
  let(:merchant) { create(:contact, :with_phone_number, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: merchant, source_id: '963900000001') }
  let(:conversation) do
    create(:conversation, contact_inbox: contact_inbox, contact: merchant, inbox: channel.inbox, account: account)
  end

  def send_template(name)
    message = create(:message, conversation: conversation, account: account, message_type: :outgoing,
                               additional_attributes: { 'template_params' => { 'name' => name, 'language' => 'en_US',
                                                                               'processed_params' => { 'body' => {} } } })
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    message.reload
  end

  before { allow(channel).to receive(:send_template).and_return('wamid.sent') }

  describe 'what may go out' do
    it 'sends an operational notice' do
      expect(send_template('integration_broken').status).not_to eq('failed')
    end

    # META'S CLASSIFICATION, NOT THE SENDER'S. The category is read off the channel's synced
    # list, so nothing an operator can type relabels a marketing template as operational.
    it 'refuses anything Meta does not classify as UTILITY' do
      message = send_template('new_feature')

      expect(message.status).to eq('failed')
      expect(message.external_error).to include('operational templates only')
    end

    # Guards the record rather than this gate: upstream refuses an unresolvable template on
    # its own ("Template not found"), so this example stays green without the gate. It is
    # here because the OUTCOME matters -- a name nobody synced must not reach Meta -- not
    # because it pins the UTILITY rule, which the example above does.
    it 'refuses a template the channel has never synced' do
      expect(send_template('invented').status).to eq('failed')
    end
  end

  # P6D insists the platform plan sets campaign_sends so platform sending is bounded. That
  # meter lives on the campaign path; without this the conversation path would bypass it and
  # the workspace would have an unmetered, unrecorded channel out.
  describe 'the allowance' do
    it 'counts every notice against the platform allowance' do
      expect { send_template('integration_broken') }
        .to change { BillingUsageCounter.where(account_id: account.id).sum(:used) }.by(1)
    end

    it 'stops once the allowance is spent' do
      2.times { send_template('integration_broken') }

      message = send_template('integration_broken')

      expect(message.status).to eq('failed')
      expect(message.external_error).to include('allowance')
    end

    # A refused template must not cost a send: the message never reached Meta.
    it 'does not spend the allowance on a template it refused' do
      expect { send_template('new_feature') }
        .not_to(change { BillingUsageCounter.where(account_id: account.id).sum(:used) })
    end
  end

  # The rules above are the PLATFORM workspace's. A merchant's workspace is unaffected --
  # it may send marketing to somebody who opted in, and its sends are metered by its own plan.
  describe 'a merchant workspace is unaffected' do
    let(:merchant_account) { create(:account) }
    let(:merchant_channel) do
      create(:channel_whatsapp, account: merchant_account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false, message_templates: templates)
    end
    let(:shopper) { create(:contact, :with_phone_number, account: merchant_account) }
    let(:shopper_inbox) do
      create(:contact_inbox, inbox: merchant_channel.inbox, contact: shopper, source_id: '963900000002')
    end
    let(:shopper_conversation) do
      create(:conversation, contact_inbox: shopper_inbox, contact: shopper, inbox: merchant_channel.inbox,
                            account: merchant_account)
    end

    before { allow(merchant_channel).to receive(:send_template).and_return('wamid.sent') }

    it 'still sends a marketing template from a merchant workspace' do
      message = create(:message, conversation: shopper_conversation, account: merchant_account,
                                 message_type: :outgoing,
                                 additional_attributes: { 'template_params' => {
                                   'name' => 'new_feature', 'language' => 'en_US',
                                   'processed_params' => { 'body' => {} }
                                 } })

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload.status).not_to eq('failed')
    end
  end
end
