require 'rails_helper'

# THE SIX CASES THE TAG HAS TO GET RIGHT, plus the two window edges.
#
# Before this rule existed, every one of these returned the tag as long as the installation switch was on. The
# switch is still necessary -- it is the operator's assertion that Meta's App Review granted the Human Agent
# permission, which no Graph endpoint will tell us -- but it is no longer sufficient, because the tag also claims
# that a human is writing and that the standard 24-hour window has closed.
describe Messages::HumanAgentTagEligibility do
  # Declared ahead of the let! blocks on purpose: the Facebook page factory subscribes the page with Meta on
  # create, and a `before` only runs before a `let!` that is declared after it.
  before do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    GlobalConfig.clear_cache
  end

  let!(:account) { create(:account) }
  let!(:channel) { create(:channel_facebook_page, account: account) }
  let!(:inbox) { create(:inbox, channel: channel, account: account) }
  let!(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  # `account:` matters: without it the conversation factory creates an account of its own, the messages below land
  # with a different account_id, and `MessageWindowService#last_incoming_message` -- which scopes by the
  # conversation's account -- finds nothing, so every window question answers false for the wrong reason.
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox, contact_inbox: contact_inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def person_wrote(ago)
    create(:message, message_type: :incoming, inbox: inbox, account: account, conversation: conversation,
                     created_at: ago)
  end

  def outgoing(sender: agent, **attributes)
    create(:message, message_type: :outgoing, inbox: inbox, account: account, conversation: conversation,
                     sender: sender, **attributes)
  end

  def eligible?(message)
    described_class.new(message: message, config_key: 'ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT').eligible?
  end

  context 'when the installation asserts the Human Agent permission' do
    around { |example| with_modified_env(ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT: 'true') { example.run } }

    it 'tags an agent reply sent after the standard window closed, which is the whole point of the tag' do
      person_wrote(48.hours.ago)

      expect(eligible?(outgoing)).to be(true)
    end

    it 'does not tag an agent reply inside the standard window, where a RESPONSE is the correct type' do
      person_wrote(2.hours.ago)

      expect(eligible?(outgoing)).to be(false)
    end

    it 'does not tag a bot reply, because no human agent is writing' do
      person_wrote(48.hours.ago)

      expect(eligible?(outgoing(sender: create(:agent_bot)))).to be(false)
    end

    it 'does not tag an automation reply' do
      person_wrote(48.hours.ago)
      rule = create(:automation_rule, account: account)

      expect(eligible?(outgoing(sender: nil, content_attributes: { automation_rule_id: rule.id }))).to be(false)
    end

    # No Campaign row, because Campaign refuses a Messenger inbox ("Unsupported Inbox type") and inventing a
    # supported one would not exercise this path. What the rule reads is the campaign_id a campaign send stamps on
    # the message (Messages::MessageBuilder#campaign_id), so that is what is set: if campaigns ever reach this
    # channel, the tag must not follow them.
    it 'does not tag a campaign send' do
      person_wrote(48.hours.ago)

      expect(eligible?(outgoing(sender: nil, additional_attributes: { campaign_id: 7 }))).to be(false)
    end

    # FAIL CLOSED, both edges. With no incoming message there is no "person's message" for a human agent to be
    # responding to within 7 days, and past 7 days the tag has expired -- Meta would refuse either send, and
    # claiming the tag anyway is the misuse that costs the permission.
    it 'does not tag a message in a conversation the person never wrote in' do
      expect(eligible?(outgoing)).to be(false)
    end

    it 'does not tag an agent reply past the 7-day human agent window' do
      person_wrote(8.days.ago)

      expect(eligible?(outgoing)).to be(false)
    end
  end

  # The one piece of Meta's state the code can act on: without the operator's assertion that App Review granted
  # the permission, the tag is never sent, however eligible the message otherwise looks.
  context 'when the installation does not assert the Human Agent permission' do
    it 'does not tag even an otherwise perfectly eligible agent reply' do
      person_wrote(48.hours.ago)

      expect(eligible?(outgoing)).to be(false)
    end
  end
end
