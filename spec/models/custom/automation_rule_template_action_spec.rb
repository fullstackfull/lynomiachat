require 'rails_helper'

# What a Commerce trigger is allowed to do to a customer (docs/pre-p7-closeout/03-template-automation-action.md).
# The rule stays what P6 set: a store event is not a customer message, and a WhatsApp conversation may be outside its
# 24-hour window — so free-form actions remain refused. The one exception is an approved template, because that is
# the only thing WhatsApp itself permits there.
RSpec.describe AutomationRule do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conditions) { [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] }
  let(:template_action) do
    { 'action_name' => 'send_whatsapp_template',
      'action_params' => [{ 'inbox_id' => inbox.id, 'name' => 'cart_reminder', 'language' => 'en',
                            'params' => { 'body' => { '1' => 'x' } } }] }
  end

  def rule(event_name, actions)
    account.automation_rules.new(name: 'Rule', event_name: event_name, conditions: conditions, actions: actions)
  end

  before { account.enable_features('lynomia_commerce') }

  describe 'the approved-template action' do
    it 'is a known action name, so a rule naming it is not refused as unsupported' do
      expect(rule('conversation_created', [template_action])).to be_valid
    end

    it 'may be used by commerce_cart_abandoned' do
      expect(rule('commerce_cart_abandoned', [template_action])).to be_valid
    end

    it 'may be used by an order trigger too' do
      expect(rule('commerce_order_paid', [template_action])).to be_valid
    end

    it 'is implemented on the action service the listener dispatches to' do
      expect(AutomationRules::ActionService.private_instance_methods(true)).to include(:send_whatsapp_template)
    end
  end

  describe 'free-form customer messages on Commerce triggers stay forbidden' do
    it 'refuses send_message' do
      invalid = rule('commerce_cart_abandoned', [{ 'action_name' => 'send_message', 'action_params' => ['hi'] }])

      expect(invalid).not_to be_valid
      expect(invalid.errors[:actions].join).to include('send_message')
    end

    it 'refuses send_attachment' do
      expect(rule('commerce_cart_abandoned', [{ 'action_name' => 'send_attachment', 'action_params' => [1] }])).not_to be_valid
    end

    it 'refuses a free-form action even when the template action is present too' do
      invalid = rule('commerce_cart_abandoned',
                     [template_action, { 'action_name' => 'send_message', 'action_params' => ['hi'] }])

      expect(invalid).not_to be_valid
    end
  end

  # A rule that saves but names a template nothing can find is an invisible no-op, which is the exact failure mode
  # P0/D8 exists to prevent.
  describe 'configuration completeness' do
    it 'refuses the action without an inbox' do
      invalid = rule('commerce_cart_abandoned',
                     [{ 'action_name' => 'send_whatsapp_template',
                        'action_params' => [{ 'name' => 'x', 'language' => 'en' }] }])

      expect(invalid).not_to be_valid
      expect(invalid.errors[:actions].join).to include('inbox_id')
    end

    it 'refuses the action without a template name or language' do
      invalid = rule('commerce_cart_abandoned',
                     [{ 'action_name' => 'send_whatsapp_template', 'action_params' => [{ 'inbox_id' => inbox.id }] }])

      expect(invalid).not_to be_valid
      expect(invalid.errors[:actions].join).to include('name').and include('language')
    end

    it 'refuses the action with no configuration at all' do
      expect(rule('commerce_cart_abandoned',
                  [{ 'action_name' => 'send_whatsapp_template', 'action_params' => [] }])).not_to be_valid
    end

    # A disabled rule is a draft. This is what lets the starter recipe create the trigger and the action and leave
    # the inbox and template to be chosen in the rule editor, instead of a second template selector in the wizard.
    it 'allows an incomplete draft while the rule is disabled' do
      draft = rule('commerce_cart_abandoned',
                   [{ 'action_name' => 'send_whatsapp_template', 'action_params' => [] }])
      draft.active = false

      expect(draft).to be_valid
    end

    it 'refuses to switch on an incomplete draft' do
      draft = rule('commerce_cart_abandoned',
                   [{ 'action_name' => 'send_whatsapp_template', 'action_params' => [] }])
      draft.active = false
      draft.save!

      draft.active = true

      expect(draft).not_to be_valid
      expect(draft.errors[:actions].join).to include('inbox_id')
    end
  end
end
