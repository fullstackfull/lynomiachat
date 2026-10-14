require 'rails_helper'

# P3E. A shopper opting out without an agent's help.
#
# An opt-out that only works when somebody reads the conversation is not an opt-out: whether a
# person's refusal takes effect would depend on how busy the merchant is that afternoon. So the
# keyword is matched on the inbound message itself, and these tests are about where the line
# between "an opt-out" and "a sentence containing the word stop" falls.
RSpec.describe Commerce::ConsentListener do
  let(:account) { create(:account) }
  let(:whatsapp) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: whatsapp.inbox, source_id: '963955111222') }
  let(:conversation) { create(:conversation, account: account, inbox: whatsapp.inbox, contact: contact, contact_inbox: contact_inbox) }

  def shopper_says(content, type: :incoming)
    message = create(:message, account: account, inbox: whatsapp.inbox, conversation: conversation,
                               message_type: type, content: content)
    described_class.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
    message
  end

  def state_of(purpose) = Commerce::MessagingConsent.find_by(contact_id: contact.id, purpose: purpose)&.state

  it 'records a withdrawal for both classes when the shopper says stop' do
    shopper_says('STOP')

    expect(state_of('transactional')).to eq('withdrawn')
    expect(state_of('promotional')).to eq('withdrawn')
  end

  # This integration's shoppers write in Arabic. An opt-out that only works in English is an
  # opt-out most of them cannot use.
  it 'understands the Arabic keywords' do
    shopper_says('إلغاء')

    expect(state_of('promotional')).to eq('withdrawn')
  end

  it 'lets a shopper opt back in' do
    shopper_says('stop')
    shopper_says('START')

    expect(state_of('transactional')).to eq('granted')
    expect(state_of('promotional')).to eq('granted')
  end

  it 'ignores case and trailing punctuation' do
    shopper_says('  Stop.  ')

    expect(state_of('promotional')).to eq('withdrawn')
  end

  # THE MATCH IS THE WHOLE MESSAGE. "Please stop sending me the wrong size" is a complaint for
  # an agent, and silencing the customer who wrote it is the opposite of helping them.
  it 'does not treat a sentence containing the word as an opt-out' do
    shopper_says('please stop sending me the wrong size')
    shopper_says('can you cancel my order?')

    expect(Commerce::MessagingConsent.count).to eq(0)
  end

  it 'ignores an outgoing message, so an agent typing the word cannot opt a shopper out' do
    shopper_says('stop', type: :outgoing)

    expect(Commerce::MessagingConsent.count).to eq(0)
  end

  # The evidence is provenance, not a transcript: a consent table is the last place a
  # customer's words should be copied to.
  it 'keeps the message id and the keyword, and no message body' do
    message = shopper_says('UNSUBSCRIBE')
    evidence = Commerce::MessagingConsent.find_by(contact_id: contact.id, purpose: 'promotional').evidence

    expect(evidence).to eq('message_id' => message.id, 'keyword' => 'unsubscribe')
  end

  it 'audits the change so who decided it and when has one answer' do
    expect { shopper_says('stop') }.to change {
      Custom::AuditLog.where(comment: 'commerce.consent_changed').count
    }.by(2)
  end
end
