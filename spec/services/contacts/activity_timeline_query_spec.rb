require 'rails_helper'

RSpec.describe Contacts::ActivityTimelineQuery do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:restricted_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:other_contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def query(user: administrator, categories: nil, **page)
    described_class.new(account: account, contact: contact, user: user, categories: categories, page: page)
  end

  def message(content: 'hello', at: 2.hours.ago, type: :incoming, private_note: false, on: nil)
    create(:message, account: account, inbox: (on || conversation).inbox, conversation: on || conversation,
                     message_type: type, private: private_note, content: content, created_at: at)
  end

  describe 'composition' do
    it 'returns the contact\'s messages newest first' do
      message(content: 'older', at: 3.hours.ago)
      message(content: 'newer', at: 1.hour.ago)

      # Only these two are asserted on: creating a conversation also creates the inbox's own system messages,
      # which are real timeline rows and legitimately sit above both.
      summaries = query.call[:payload].pluck(:summary) & %w[older newer]

      expect(summaries).to eq(%w[newer older])
    end

    it 'reports the conversation opening as its own entry' do
      conversation

      kinds = query.call[:payload].pluck(:kind)

      expect(kinds).to include('conversation_created')
    end

    it 'gives every entry a stable composite id and a category' do
      message

      entry = query.call[:payload].find { |row| row[:kind] == 'message_incoming' }

      expect(entry[:id]).to match(/\Amessages:\d+\z/)
      expect(entry[:category]).to eq('messages')
      expect(entry[:conversation_id]).to eq(conversation.id)
    end

    it 'truncates a long message rather than returning the whole body' do
      message(content: 'x' * 1000)

      entry = query.call[:payload].find { |row| row[:kind] == 'message_incoming' }

      expect(entry[:summary].length).to be <= Contacts::ActivityTimeline::Entry.summary_limit + 3
    end

    it 'includes a private note with its own kind, as the conversation view does' do
      message(content: 'internal', type: :outgoing, private_note: true)

      expect(query.call[:payload].pluck(:kind)).to include('private_note')
    end

    it 'reads activity messages under their own source so they never collide with messages' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity,
                       content: 'Conversation was marked resolved by Ada',
                       content_attributes: { activity: { type: 'conversation_status_changed', status: 'resolved' } },
                       created_at: 1.hour.ago)

      entry = query.call[:payload].find { |row| row[:kind] == 'conversation_status_changed' }

      expect(entry[:id]).to start_with('activity_message:')
      expect(entry[:meta][:status]).to eq('resolved')
      expect(entry[:meta][:structured]).to be(true)
    end

    it 'surfaces a prose activity message as recorded text without parsing it' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity,
                       content: 'Assigned to Ada by Grace', created_at: 1.hour.ago)

      entry = query.call[:payload].find { |row| row[:kind] == 'conversation_activity' }

      expect(entry[:summary]).to eq('Assigned to Ada by Grace')
      expect(entry[:meta][:structured]).to be(false)
    end
  end

  describe 'tenant and record isolation' do
    it "never returns another contact's activity" do
      other_conversation = create(:conversation, account: account, inbox: inbox, contact: other_contact)
      message(content: 'not theirs', on: other_conversation)

      expect(query.call[:payload].pluck(:summary)).not_to include('not theirs')
    end

    it "never returns another account's activity" do
      foreign_inbox = create(:inbox, account: other_account)
      foreign_contact = create(:contact, account: other_account)
      foreign_conversation = create(:conversation, account: other_account, inbox: foreign_inbox, contact: foreign_contact)
      create(:message, account: other_account, inbox: foreign_inbox, conversation: foreign_conversation,
                       message_type: :incoming, content: 'foreign', created_at: 1.hour.ago)

      expect(query.call[:payload]).to be_empty
    end

    it 'hides activity in a conversation the caller cannot open' do
      create(:inbox_member, user: restricted_agent, inbox: inbox)
      hidden = create(:conversation, account: account, inbox: other_inbox, contact: contact)
      message(content: 'visible')
      message(content: 'hidden', on: hidden)

      summaries = query(user: restricted_agent).call[:payload].pluck(:summary)

      expect(summaries).to include('visible')
      expect(summaries).not_to include('hidden')
    end

    it 'shows an administrator every inbox' do
      hidden = create(:conversation, account: account, inbox: other_inbox, contact: contact)
      message(content: 'other inbox', on: hidden)

      expect(query.call[:payload].pluck(:summary)).to include('other inbox')
    end
  end

  describe 'pagination' do
    before { 5.times { |index| message(content: "m#{index}", at: (index + 1).hours.ago) } }

    it 'is bounded by default' do
      expect(query.call[:meta][:limit]).to eq(described_class::DEFAULT_LIMIT)
    end

    it 'returns a cursor when more remains and follows it without repeating or skipping a row' do
      first = query(limit: 2).call
      expect(first[:payload].length).to eq(2)
      expect(first[:meta][:next_cursor]).to be_present

      second = query(limit: 2, cursor: first[:meta][:next_cursor]).call
      ids = first[:payload].pluck(:id) + second[:payload].pluck(:id)

      expect(ids.uniq.length).to eq(ids.length)
      expect(second[:payload].length).to eq(2)
    end

    it 'walks the whole timeline in pages with no gaps' do
      all_ids = query(limit: 100).call[:payload].pluck(:id)

      paged = []
      cursor = nil
      loop do
        page = query(limit: 2, cursor: cursor).call
        paged += page[:payload].pluck(:id)
        cursor = page[:meta][:next_cursor]
        break if cursor.nil?
      end

      expect(paged).to eq(all_ids)
    end

    it 'has no cursor on the last page' do
      expect(query(limit: 100).call[:meta][:next_cursor]).to be_nil
    end

    it 'refuses a limit above the maximum' do
      expect { query(limit: described_class::MAX_LIMIT + 1) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Timeline::InvalidLimit') })
    end

    it 'refuses a limit of zero' do
      expect { query(limit: 0) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Timeline::InvalidLimit') })
    end

    it 'refuses a malformed cursor rather than returning a wrong page' do
      expect { query(cursor: 'not-a-cursor') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Timeline::InvalidCursor') })
    end
  end

  describe 'categories' do
    before do
      message(content: 'a message')
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity,
                       content: 'Marked resolved', created_at: 1.hour.ago)
    end

    it 'defaults to every category' do
      expect(query.call[:meta][:categories]).to eq(%w[messages conversations campaigns automations commerce tickets])
    end

    it 'narrows to one category' do
      result = query(categories: ['messages']).call

      expect(result[:meta][:categories]).to eq(['messages'])
      expect(result[:payload].pluck(:category).uniq).to eq(['messages'])
    end

    it 'refuses an unknown category' do
      expect { query(categories: %w[messages invoices]) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Timeline::UnsupportedCategory') })
    end
  end

  describe 'degradation' do
    it 'reports an optional adapter failure as a warning and still returns the communication' do
      message(content: 'still here')
      broken = instance_double(Contacts::ActivityTimeline::CommerceAdapter, source: 'commerce')
      allow(broken).to receive(:fetch).and_raise(ActiveRecord::StatementInvalid, 'boom')
      allow(Contacts::ActivityTimeline::CommerceAdapter).to receive(:new).and_return(broken)

      result = query.call

      expect(result[:payload].pluck(:summary)).to include('still here')
      expect(result[:meta][:partial]).to be(true)
      expect(result[:meta][:warnings]).to include({ scope: 'commerce', reason: 'unavailable' })
    end

    it 'raises rather than hiding a failure in the contact\'s own messages' do
      broken = instance_double(Contacts::ActivityTimeline::MessagesAdapter, source: 'messages')
      allow(broken).to receive(:fetch).and_raise(ActiveRecord::StatementInvalid, 'boom')
      allow(Contacts::ActivityTimeline::MessagesAdapter).to receive(:new).and_return(broken)

      expect { query.call }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'is not partial when every adapter succeeds' do
      message

      expect(query.call[:meta][:partial]).to be(false)
    end
  end
end
