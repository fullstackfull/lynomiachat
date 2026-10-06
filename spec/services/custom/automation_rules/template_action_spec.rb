require 'rails_helper'

RSpec.describe Custom::AutomationRules::TemplateAction do
  let(:account) { create(:account) }
  let(:templates) do
    [{ 'name' => 'cart_reminder', 'language' => 'en', 'status' => 'approved', 'category' => 'MARKETING',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hi {{1}}, your cart is waiting: {{2}}' }] },
     { 'name' => 'cart_pending', 'language' => 'en', 'status' => 'PENDING', 'category' => 'MARKETING',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hi {{1}}' }] },
     { 'name' => 'cart_rejected', 'language' => 'en', 'status' => 'REJECTED', 'category' => 'MARKETING',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hi {{1}}' }] },
     { 'name' => 'cart_paused', 'language' => 'en', 'status' => 'PAUSED', 'category' => 'MARKETING',
       'components' => [{ 'type' => 'BODY', 'text' => 'Hi {{1}}' }] },
     { 'name' => 'login_code', 'language' => 'en', 'status' => 'approved', 'category' => 'AUTHENTICATION',
       'components' => [{ 'type' => 'BODY', 'text' => 'Code {{1}}' }] }]
  end
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false, message_templates: templates)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, name: 'Noura', phone_number: '+96512345678') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '96512345678') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:rule) do
    create(:automation_rule, account: account, event_name: 'conversation_created',
                             actions: [{ 'action_name' => 'add_label', 'action_params' => ['x'] }])
  end
  let(:mapping) { { 'body' => { '1' => '{{contact.name}}', '2' => 'https://shop.example/cart/9' } } }

  def run(config)
    described_class.new(rule: rule, account: account, conversation: conversation, config: config).perform
  end

  def config(overrides = {})
    { 'inbox_id' => inbox.id, 'name' => 'cart_reminder', 'language' => 'en', 'params' => mapping }.merge(overrides)
  end

  describe 'sending an approved template' do
    # `content_mode` arrives as `raw_template` and the existing pipeline rewrites it to `rendered` once Liquid has
    # run over the params (app/models/concerns/liquidable.rb:51). That is the same thing that happens to a Send
    # template flow node, and asserting it here is what proves the action went through the existing path rather
    # than around it.
    it 'creates one outgoing message carrying template_params the existing sender understands' do
      result = run(config)

      expect(result).to be_sent
      message = conversation.messages.reload.last
      expect(message).to have_attributes(message_type: 'outgoing', private: false)
      expect(message.additional_attributes['template_params']).to include(
        'name' => 'cart_reminder', 'language' => 'en', 'category' => 'MARKETING', 'content_mode' => 'rendered'
      )
    end

    it 'fills the mapping from the contact rather than from the rule' do
      run(config)

      params = conversation.messages.reload.last.additional_attributes.dig('template_params', 'processed_params')
      expect(params['body']).to eq('1' => 'Noura', '2' => 'https://shop.example/cart/9')
    end

    it 'carries no credential in the action payload' do
      expect(config.keys).to contain_exactly('inbox_id', 'name', 'language', 'params')
    end
  end

  describe 'sendability' do
    it 'refuses a template Meta has never approved' do
      expect(run(config('name' => 'cart_pending')).reason).to eq('template_not_approved')
    end

    it 'refuses a rejected template' do
      expect(run(config('name' => 'cart_rejected')).reason).to eq('template_not_approved')
    end

    it 'refuses a paused or disabled template' do
      expect(run(config('name' => 'cart_paused')).reason).to eq('template_not_approved')
    end

    # A local draft exists as a Whatsapp::MessageTemplate row but never reaches the channel's synced snapshot, and
    # the snapshot is the gate the sender itself uses — so the draft is invisible to a send, by design.
    it 'refuses a local draft that Meta has never seen' do
      draft = Whatsapp::MessageTemplate.create!(account: account, business_account_id: 'waba-1', name: 'local_draft',
                                                language: 'en', category: 'MARKETING',
                                                components: [{ 'type' => 'BODY', 'text' => 'Hi {{1}}' }])
      expect(draft.meta_status).to be_nil

      expect(run(config('name' => 'local_draft')).reason).to eq('template_not_found')
    end

    it 'refuses a template in a language this inbox does not have' do
      expect(run(config('language' => 'ar')).reason).to eq('template_language_unavailable')
    end

    it 'refuses an authentication template the composer would not send either' do
      expect(run(config('name' => 'login_code', 'params' => { 'body' => { '1' => '123' } })).reason).to eq('template_not_allowed')
    end

    it 'refuses when a variable the template requires is unresolved' do
      expect(run(config('params' => { 'body' => { '1' => '{{contact.name}}' } })).reason).to eq('template_param_missing')
    end

    it 'refuses an unknown token rather than sending it literally' do
      expect(run(config('params' => { 'body' => { '1' => '{{cart.nope}}', '2' => 'x' } })).reason).to eq('template_param_missing')
    end

    it 'sends nothing at all when it refuses' do
      run(config('name' => 'cart_rejected'))

      expect(conversation.messages.reload).to be_empty
    end
  end

  describe 'account and WABA isolation' do
    it 'refuses an inbox that belongs to another account' do
      other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

      expect(run(config('inbox_id' => other.inbox.id)).reason).to eq('inbox_not_in_account')
    end

    # The gate reads THIS inbox's synced snapshot, so a template that lives on another WABA is simply absent.
    it 'refuses a template that belongs to another WABA' do
      other = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false,
                                        message_templates: [{ 'name' => 'other_waba_only', 'language' => 'en',
                                                              'status' => 'approved', 'category' => 'UTILITY',
                                                              'components' => [{ 'type' => 'BODY', 'text' => 'hi' }] }])
      expect(other.inbox).to be_present

      expect(run(config('name' => 'other_waba_only')).reason).to eq('template_not_found')
    end

    it 'refuses a non-WhatsApp inbox' do
      expect(run(config('inbox_id' => create(:inbox, account: account).id)).reason).to eq('channel_not_whatsapp')
    end

    it 'refuses when the conversation is not on the configured inbox' do
      elsewhere = create(:conversation, account: account, contact: contact)
      result = described_class.new(rule: rule, account: account, conversation: elsewhere, config: config).perform

      expect(result.reason).to eq('conversation_inbox_mismatch')
    end
  end

  describe 'contact availability' do
    it 'refuses a blocked contact' do
      contact.update!(blocked: true)

      expect(run(config).reason).to eq('contact_unavailable')
    end
  end
end
