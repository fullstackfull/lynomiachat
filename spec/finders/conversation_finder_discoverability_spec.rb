require 'rails_helper'

# The discoverability assertions the P7 brief asks for by name. The working queue defaults to Open deliberately
# and that default is not being changed; what these prove is that nothing ELSE narrows the list behind the
# agent's back, and that the conversations easiest to lose - a resolved one, one the business started, one whose
# reply failed - are all still reachable.
describe ConversationFinder do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    Current.account = account
  end

  def find(params) = described_class.new(agent, params).perform[:conversations]

  describe 'the default working queue' do
    let!(:mine) { create(:conversation, account: account, inbox: inbox, assignee: agent) }
    let!(:someone_elses) { create(:conversation, account: account, inbox: inbox, assignee: create(:user, account: account)) }
    let!(:unassigned) { create(:conversation, account: account, inbox: inbox) }
    let!(:resolved) { create(:conversation, account: account, inbox: inbox, status: 'resolved') }

    # Open is the default on purpose. The point of this example is that it is the ONLY thing narrowing the list:
    # no assignee, no inbox, no label and no time window is applied unless asked for.
    it 'narrows by nothing but the Open status and the inboxes the agent belongs to' do
      expect(find({})).to contain_exactly(mine, someone_elses, unassigned)
    end

    it 'leaves nothing out of an explicit all-status request' do
      expect(find({ status: 'all' })).to contain_exactly(mine, someone_elses, unassigned, resolved)
    end

    # What "clear the filters" has to restore: the full permitted set, not the default queue.
    it 'returns the same set after a narrowing filter is dropped again' do
      narrowed = find({ status: 'resolved' })
      restored = find({ status: 'all' })

      expect(narrowed).to contain_exactly(resolved)
      expect(restored).to contain_exactly(mine, someone_elses, unassigned, resolved)
    end

    # Every conversation gets an explicit last_activity_at, because the point is the ORDER: leaving any of them on
    # its creation timestamp would let the database decide where it lands and the assertion would pass by luck.
    it 'is deterministic: an explicit order is applied, not left to the database' do
      [resolved, someone_elses, mine, unassigned].each_with_index do |conversation, index|
        conversation.update!(last_activity_at: Time.zone.parse('2026-07-21 10:00:00') + index.hours)
      end

      expect(find({ status: 'all' })).to eq([unassigned, mine, someone_elses, resolved])
      expect(find({ status: 'all', sort_by: 'last_activity_at_asc' })).to eq([resolved, someone_elses, mine, unassigned])
    end

    it 'never reaches an inbox the agent is not a member of' do
      other_inbox = create(:inbox, account: account)
      hidden = create(:conversation, account: account, inbox: other_inbox)

      expect(find({ status: 'all' })).not_to include(hidden)
    end
  end

  # A conversation the business started - a campaign send, an API-created conversation - has no incoming message
  # at all. It must still appear, because "nothing from the customer yet" is exactly when somebody needs to see it.
  describe 'a conversation the business started' do
    let!(:outbound_first) { create(:conversation, account: account, inbox: inbox) }

    before do
      create(:message, account: account, inbox: inbox, conversation: outbound_first, message_type: :outgoing,
                       content: 'Your order has shipped')
    end

    it 'is in the default queue' do
      expect(find({})).to include(outbound_first)
    end

    it 'is in the unassigned queue, where nobody has picked it up yet' do
      expect(find({ assignee_type: 'unassigned' })).to include(outbound_first)
    end

    it 'is still there when its only message failed to send' do
      outbound_first.messages.each { |message| message.update!(status: :failed) }

      expect(find({})).to include(outbound_first)
      expect(find({ status: 'all' })).to include(outbound_first)
    end
  end

  describe 'a resolved conversation' do
    let!(:resolved) { create(:conversation, account: account, inbox: inbox, assignee: agent, status: 'resolved') }

    it 'is reachable by asking for it' do
      expect(find({ status: 'resolved' })).to contain_exactly(resolved)
    end

    it 'is reachable through all statuses' do
      expect(find({ status: 'all' })).to include(resolved)
    end

    it 'is reachable by its own id regardless of the status filter' do
      expect(find({ status: 'all', assignee_type: 'me' })).to include(resolved)
    end

    # The one that would hurt: a reply failed, somebody resolved the conversation anyway, and the failure is now
    # outside the default queue. It is still findable, which is what the message-delivery filter is for.
    it 'is findable by its failed message even after being resolved' do
      create(:message, account: account, inbox: inbox, conversation: resolved, message_type: :outgoing,
                       status: :failed)

      payload = [{ attribute_key: 'message_status', filter_operator: 'equal_to', values: ['failed'],
                   query_operator: nil }.with_indifferent_access]

      expect(Conversations::FilterService.new({ payload: payload }, agent, account).perform[:conversations])
        .to contain_exactly(resolved)
    end
  end
end
