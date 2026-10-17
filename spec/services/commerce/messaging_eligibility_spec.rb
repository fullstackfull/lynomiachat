require 'rails_helper'

# P3E. The consent foundation, and specifically the thing it exists to get right: transactional
# and promotional are different questions with OPPOSITE defaults.
#
# A test suite that only checked "an opt-out blocks a send" would pass against a model that
# treats the two classes identically -- which is the failure this is here to prevent in both
# directions. So every case below is written twice where the classes differ, and says which
# answer is correct for each and why.
RSpec.describe Commerce::MessagingEligibility do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  def record(state, purposes: Commerce::MessagingConsents::PURPOSES, source: 'test')
    Commerce::MessagingConsents.record(
      account: account, contact: contact,
      decision: Commerce::MessagingConsents::Decision.new(state: state, source: source, purposes: purposes)
    )
  end

  describe 'the defaults, which are opposite' do
    # The shopper placed the order. Being told it shipped is the service they asked for, and
    # withholding it for want of a marketing opt-in is a worse outcome for them.
    it 'allows a transactional message to a shopper who has recorded nothing' do
      expect(described_class.refusal(contact, :transactional)).to be_nil
    end

    # An abandoned basket is not a transaction they completed and not a message they asked for.
    # The absence of a row is not a grant.
    it 'refuses a promotional message to a shopper who has recorded nothing' do
      expect(described_class.refusal(contact, :promotional)).to eq(:promotional_consent_missing)
    end
  end

  describe 'a shopper who said stop' do
    before { record(:withdrawn) }

    it 'refuses both classes, because that is what the person meant' do
      expect(described_class.refusal(contact, :transactional)).to eq(:consent_withdrawn)
      expect(described_class.refusal(contact, :promotional)).to eq(:consent_withdrawn)
    end
  end

  describe 'a shopper who agreed to marketing' do
    before { record(:granted, purposes: ['promotional'], source: 'checkout_opt_in') }

    it 'allows promotional messages, and has changed nothing about transactional ones' do
      expect(described_class.refusal(contact, :promotional)).to be_nil
      expect(described_class.refusal(contact, :transactional)).to be_nil
    end
  end

  # A grant for one class is never a grant for the other, in either direction.
  it 'does not let a transactional grant admit a promotional message' do
    record(:granted, purposes: ['transactional'])

    expect(described_class.refusal(contact, :transactional)).to be_nil
    expect(described_class.refusal(contact, :promotional)).to eq(:promotional_consent_missing)
  end

  it 'does not let a promotional withdrawal silence an order update' do
    record(:withdrawn, purposes: ['promotional'])

    expect(described_class.refusal(contact, :promotional)).to eq(:consent_withdrawn)
    expect(described_class.refusal(contact, :transactional)).to be_nil
  end

  describe 'suppression' do
    before { record(:suppressed, source: 'provider_undeliverable') }

    it 'blocks both classes and is reported as its own reason, not as a withdrawal' do
      expect(described_class.refusal(contact, :transactional)).to eq(:messaging_suppressed)
      expect(described_class.refusal(contact, :promotional)).to eq(:messaging_suppressed)
    end

    # An operator fixing a delivery fault must not be able to overturn a person's opt-out by
    # doing so, so the two are cleared separately and the clear only touches suppression.
    it 'is cleared without touching a withdrawal the shopper made' do
      record(:withdrawn, purposes: ['promotional'])
      Commerce::MessagingConsents.clear_suppression(account: account, contact: contact, source: 'operator')

      expect(described_class.refusal(contact, :transactional)).to be_nil
      expect(described_class.refusal(contact, :promotional)).to eq(:consent_withdrawn)
    end
  end

  # The existing gate, kept and checked FIRST: a blocked contact is refused before any consent
  # row is even looked at, so blocking cannot be defeated by granting consent.
  it 'refuses a blocked contact whatever they consented to' do
    record(:granted)
    contact.update!(blocked: true)

    expect(described_class.refusal(contact, :promotional)).to eq(:contact_unavailable)
    expect(described_class.refusal(contact, :transactional)).to eq(:contact_unavailable)
  end

  it 'refuses when there is no contact at all rather than deciding about nobody' do
    expect(described_class.refusal(nil, :transactional)).to eq(:contact_unavailable)
  end

  describe 'which class a trigger belongs to' do
    it 'treats every order trigger as transactional and the cart trigger as promotional' do
      Commerce::OrderTransitions::EVENTS.each do |event|
        expect(described_class.purpose_for(event)).to eq(:transactional), event
      end

      expect(described_class.purpose_for('commerce_cart_abandoned')).to eq(:promotional)
    end

    # THE DEFAULT HAS TO BE THE CONSERVATIVE ONE for a commerce trigger: one added later
    # without a classification must not be able to reach people who never opted in just
    # because nobody updated a hash.
    it 'treats an unclassified commerce trigger as promotional' do
      allow(Automation::CommerceEvents).to receive(:event?).with('commerce_something_new').and_return(true)

      expect(described_class.purpose_for('commerce_something_new')).to eq(:promotional)
    end

    # A trigger that is not about commerce at all has no commerce class. Inventing one would
    # demand a marketing opt-in before answering a conversation the customer just started,
    # which is a worse outcome for them than the message.
    it 'gives an ordinary automation trigger no commerce class' do
      expect(described_class.purpose_for('conversation_created')).to be_nil
    end

    it 'still lets a withdrawal or a suppression block a message with no commerce class' do
      expect(described_class.refusal(contact, nil)).to be_nil

      record(:withdrawn, purposes: ['promotional'])
      expect(described_class.refusal(contact, nil)).to eq(:consent_withdrawn)
    end

    it 'reports a suppression as its own reason with no commerce class too' do
      record(:suppressed, purposes: ['transactional'], source: 'provider_undeliverable')

      expect(described_class.refusal(contact, nil)).to eq(:messaging_suppressed)
    end

    it 'classifies every trigger the automation engine offers' do
      expect(Automation::CommerceEvents::EVENTS - described_class::PURPOSES.keys).to be_empty
    end
  end
end
