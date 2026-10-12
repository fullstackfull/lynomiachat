require 'rails_helper'

# The OSS concern keeps a channel's broken state entirely in Redis, with no TTL and no Postgres row
# (app/models/concerns/reauthorizable.rb:20-72). This is the durable half.
RSpec.describe Custom::Reauthorizable do
  let(:account) { create(:account) }
  # Reauthorizable is included by exactly five channel types plus Integrations::Hook and AutomationRule -- not
  # by every channel. Channel::WebWidget, which the generic :inbox factory builds, has no reauthorization
  # concept at all, so an email channel is what this has to be tested against.
  let(:channel) { create(:channel_email, account: account, imap_enabled: true) }
  let(:inbox) { channel.inbox }

  it 'is prepended into the concern, so every including channel sees it' do
    expect(Reauthorizable.ancestors).to include(described_class)
    expect(Channel::Email.ancestors).to include(described_class)
    expect(Channel::Whatsapp.ancestors).to include(described_class)
  end

  describe 'prompt_reauthorization!' do
    it 'records one durable signal against the inbox' do
      channel.prompt_reauthorization!

      signal = Operations::Signal.open_signals.find_by(source: 'channel', signal: 'reauthorization_required')
      expect(signal).to be_present
      expect(signal.account_id).to eq(account.id)
      expect(signal.subject).to eq(inbox)
      expect(signal.severity).to eq('critical')
      expect(signal.detail['channel_type']).to eq(channel.class.name)
    end

    # The concern already computes `state_changed`; a channel failing once a minute must not produce a row a
    # minute.
    it 'records nothing the second time, because the state did not change' do
      channel.prompt_reauthorization!
      expect { channel.prompt_reauthorization! }.not_to change(Operations::Signal, :count)
    end

    it 'leaves the Redis flag the UI reads exactly as it was' do
      channel.prompt_reauthorization!

      expect(channel.reauthorization_required?).to be(true)
    end
  end

  describe 'reauthorized!' do
    it 'resolves the signal when the channel is reconnected' do
      channel.prompt_reauthorization!
      channel.reauthorized!

      expect(Operations::Signal.open_signals.count).to eq(0)
      expect(Operations::Signal.resolved.count).to eq(1)
    end

    it 'does nothing when the channel was not flagged' do
      expect { channel.reauthorized! }.not_to change(Operations::Signal, :count)
    end
  end

  # Reauthorizable is also included by AutomationRule and Integrations::Hook, which have no inbox. Recording
  # against a subject the console has no page for would be worse than not recording.
  describe 'an including object with no inbox' do
    it 'records nothing and does not raise' do
      rule = create(:automation_rule, account: account, event_name: 'conversation_created')

      expect { rule.prompt_reauthorization! }.not_to change(Operations::Signal, :count)
      expect(rule.reload.active).to be(false)
    end
  end
end
