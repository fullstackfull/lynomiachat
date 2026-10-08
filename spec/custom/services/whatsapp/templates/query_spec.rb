require 'rails_helper'

# The one door every surface reads templates through, and the deliberate difference between the two questions it
# answers: management reads the reconciled rows, while "what can this inbox send" reads the channel's own synced
# snapshot under the stricter product rule. A send must not depend on a projection having run, which is why the
# snapshot stays the gate.
describe Whatsapp::Templates::Query do
  subject(:query) { described_class.new(account) }

  let(:account) { create(:account) }
  # The channel factory fixes the WABA itself, so a second WABA is set after the fact.
  let(:waba_id) { '123456789' }
  let(:sendable) do
    { 'id' => '1', 'name' => 'order_shipped', 'language' => 'en_US', 'category' => 'UTILITY', 'status' => 'APPROVED',
      'components' => [{ 'type' => 'BODY', 'text' => 'Shipped in {{1}} days' }] }
  end
  let(:not_approved) { sendable.merge('id' => '2', 'name' => 'pending_one', 'status' => 'PENDING') }
  let(:authentication) do
    sendable.merge('id' => '3', 'name' => 'otp', 'category' => 'AUTHENTICATION',
                   'components' => [{ 'type' => 'BODY', 'text' => 'Your code is {{1}}' }])
  end

  let!(:channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                              provider: 'whatsapp_cloud',
                              message_templates: [sendable, not_approved, authentication])
  end

  describe '#for_inbox' do
    it 'returns the managed rows of that inbox\'s own WABA' do
      mine = Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba_id, name: 'mine',
                                               language: 'en', category: 'UTILITY', parameter_format: 'POSITIONAL',
                                               components: [{ 'type' => 'BODY', 'text' => 'Hi' }])
      other_waba = Whatsapp::MessageTemplate.create!(account: account, business_account_id: 'other-waba',
                                                     name: 'theirs', language: 'en', category: 'UTILITY',
                                                     parameter_format: 'POSITIONAL',
                                                     components: [{ 'type' => 'BODY', 'text' => 'Hi' }])

      expect(query.for_inbox(channel.inbox)).to include(mine)
      expect(query.for_inbox(channel.inbox)).not_to include(other_waba)
    end

    it 'returns nothing for an inbox that is not a WhatsApp inbox at all' do
      expect(query.for_inbox(create(:inbox, account: account))).to be_empty
    end
  end

  # Exactly the rule the composer and the campaign picker already apply, read from the snapshot rather than from a
  # row, so selection cannot drift from what a send will accept.
  describe '#sendable_for' do
    it 'offers only the approved templates that pass the product rule' do
      expect(query.sendable_for(channel.inbox).pluck('name')).to eq(['order_shipped'])
    end

    it 'excludes a template Meta has not approved' do
      expect(query.sendable_for(channel.inbox).pluck('name')).not_to include('pending_one')
    end

    it 'excludes an authentication template, which selection refuses even though a send would not' do
      expect(query.sendable_for(channel.inbox).pluck('name')).not_to include('otp')
    end

    it 'returns nothing for an inbox with no snapshot' do
      expect(query.sendable_for(create(:inbox, account: account))).to be_empty
    end
  end
end
