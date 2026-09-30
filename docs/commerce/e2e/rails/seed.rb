# Lynomia Commerce E2E data (docs/commerce/09-woocommerce-e2e.md). Stores are connected later through the UI/API.
Current.reset
password = 'Password1!x'
account_a = Account.create!(name: 'Lynomia Demo A', locale: 'en')
account_b = Account.create!(name: 'Lynomia Demo B', locale: 'en')
[account_a, account_b].each { |account| account.enable_features!('lynomia_commerce') }

def user(email, name, account, role, password)
  user = User.create!(email: email, name: name, password: password, password_confirmation: password, confirmed_at: Time.current)
  AccountUser.create!(account: account, user: user, role: role)
  user
end
admin_a = user('admin_a@commerce.lynomia.local', 'Admin A', account_a, :administrator, password)
agent_a = user('agent_a@commerce.lynomia.local', 'Agent A', account_a, :agent, password)
outsider_a = user('outsider_a@commerce.lynomia.local', 'Agent without inbox', account_a, :agent, password)
admin_b = user('admin_b@commerce.lynomia.local', 'Admin B', account_b, :administrator, password)

def whatsapp_inbox(account, name, number)
  channel = Channel::Whatsapp.new(account: account, phone_number: number, provider: 'whatsapp_cloud',
                                  provider_config: { 'api_key' => 'e2e-not-a-real-token', 'phone_number_id' => "pn#{number.delete('+')}",
                                                     'business_account_id' => 'e2e', 'source' => 'embedded_signup' })
  channel.define_singleton_method(:validate_provider_config) { nil }
  channel.define_singleton_method(:sync_templates) { nil }
  channel.save!(validate: false)
  Inbox.create!(account: account, channel: channel, name: name)
end
wa_a = whatsapp_inbox(account_a, 'واتساب بزنس', '+966110000001')
widget_channel = Channel::WebWidget.create!(account: account_a, website_url: 'https://www.syriacosmetics.example')
widget_a = Inbox.create!(account: account_a, channel: widget_channel, name: 'Website')
wa_b = whatsapp_inbox(account_b, 'WhatsApp B', '+966110000002')
[wa_a, widget_a].each { |inbox| InboxMember.create!(inbox: inbox, user: agent_a) }

def conversation(account, inbox, name:, source_id:, phone: nil, email: nil, text:)
  contact = account.contacts.create!(name: name, phone_number: phone, email: email)
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: source_id)
  conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  conv.messages.create!(account: account, inbox: inbox, message_type: :incoming, content: text, sender: contact)
  conv
end
convs = {
  omar: conversation(account_a, wa_a, name: 'Omar Khalil', source_id: '966551112233', phone: '+966551112233', text: 'مرحبا، وين وصل طلبي؟'),
  layla: conversation(account_a, wa_a, name: 'ليلى حداد', source_id: '966501234567', phone: '+966501234567', text: 'Hi, I want to check my orders'),
  sara: conversation(account_a, wa_a, name: 'Sara Ali', source_id: '966550000111', phone: '+966550000111', text: 'Hello, is my order shipped?'),
  mona: conversation(account_a, widget_a, name: 'منى صالح', source_id: SecureRandom.uuid, email: 'mona.saleh@example.com', text: 'Do you have the rose serum?'),
  visitor: conversation(account_a, widget_a, name: 'Website visitor', source_id: SecureRandom.uuid, email: 'Omar.Khalil@Example.com', text: 'I ordered as a guest'),
  hana: conversation(account_a, widget_a, name: 'Hana Saeed', source_id: SecureRandom.uuid, email: 'family@example.com', text: 'Question about an order'),
  nobody: conversation(account_a, widget_a, name: 'New lead', source_id: SecureRandom.uuid, email: 'new.lead@example.com', text: 'Hello'),
  layla_b: conversation(account_b, wa_b, name: 'ليلى حداد', source_id: '966501234567', phone: '+966501234567', text: 'مرحبا')
}
puts({ account_a: account_a.id, account_b: account_b.id, admin_a: admin_a.id, agent_a: agent_a.id, outsider_a: outsider_a.id, admin_b: admin_b.id,
       conversations: convs.transform_values(&:display_id) }.to_json)
