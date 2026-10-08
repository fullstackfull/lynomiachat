require 'rails_helper'

# A reply that WhatsApp refused is recorded on the MESSAGE. Nothing on the conversation reflects it, so until this
# filter existed the only way to find such a conversation was to already know which customer it was
# (docs/p7/10-failed-message-discoverability.md). `message_status` asks whether a conversation contains a message
# with a given delivery status.
describe Conversations::FilterService do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

  let!(:one_failure) { create(:conversation, account: account, inbox: inbox) }
  let!(:two_failures) { create(:conversation, account: account, inbox: inbox) }
  let!(:delivered_only) { create(:conversation, account: account, inbox: inbox) }
  let!(:no_messages) { create(:conversation, account: account, inbox: inbox) }

  before do
    create(:inbox_member, user: user, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: one_failure, message_type: :outgoing, status: :failed)
    create(:message, account: account, inbox: inbox, conversation: two_failures, message_type: :outgoing, status: :failed)
    create(:message, account: account, inbox: inbox, conversation: two_failures, message_type: :outgoing, status: :failed)
    create(:message, account: account, inbox: inbox, conversation: two_failures, message_type: :outgoing, status: :sent)
    create(:message, account: account, inbox: inbox, conversation: delivered_only, message_type: :outgoing, status: :delivered)
  end

  def filter(payload)
    described_class.new({ payload: payload.map(&:with_indifferent_access), page: 1 }, user, account).perform
  end

  def condition(operator, values, query_operator: nil)
    { attribute_key: 'message_status', filter_operator: operator, values: values, query_operator: query_operator }
  end

  it 'finds the conversations that contain a failed message' do
    expect(filter([condition('equal_to', ['failed'])])[:conversations]).to contain_exactly(one_failure, two_failures)
  end

  # A join would return the conversation once per failed message, which would both duplicate rows and make the
  # counts wrong. The query is a correlated EXISTS for exactly this reason.
  it 'returns a conversation with several failed messages once' do
    conversations = filter([condition('equal_to', ['failed'])])[:conversations]

    expect(conversations.map(&:id)).to eq(conversations.map(&:id).uniq)
    expect(filter([condition('equal_to', ['failed'])])[:count][:all_count]).to eq(2)
  end

  it 'finds the conversations with no failed message, including one with no messages at all' do
    expect(filter([condition('not_equal_to', ['failed'])])[:conversations]).to contain_exactly(delivered_only, no_messages)
  end

  it 'accepts several statuses at once' do
    expect(filter([condition('equal_to', %w[failed delivered])])[:conversations])
      .to contain_exactly(one_failure, two_failures, delivered_only)
  end

  # The enum lookup returns nil for a name this version does not have, so the condition becomes `IN (NULL)`.
  # Matching nothing is the safe outcome; matching everything would be a silent lie.
  it 'returns nothing for a status name that does not exist' do
    expect(filter([condition('equal_to', ['abandoned'])])[:conversations]).to be_empty
  end

  it 'combines with another condition' do
    two_failures.update!(status: :resolved)
    payload = [
      condition('equal_to', ['failed'], query_operator: 'AND'),
      { attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }
    ]

    expect(filter(payload)[:conversations]).to contain_exactly(one_failure)
  end

  it 'refuses an operator the configuration does not allow' do
    expect { filter([condition('contains', ['failed'])]) }
      .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::CustomFilter::InvalidOperator') })
  end

  it 'refuses a value that is not a string' do
    expect { filter([condition('equal_to', [{ status: 'failed' }])]) }
      .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::CustomFilter::InvalidValue') })
  end

  it 'does not reach another account\'s conversations' do
    other_account = create(:account)
    other_user = create(:user, account: other_account, role: :administrator)
    other_inbox = create(:inbox, account: other_account)
    create(:inbox_member, user: other_user, inbox: other_inbox)
    other_conversation = create(:conversation, account: other_account, inbox: other_inbox)
    create(:message, account: other_account, inbox: other_inbox, conversation: other_conversation,
                     message_type: :outgoing, status: :failed)

    result = described_class.new(
      { payload: [condition('equal_to', ['failed']).with_indifferent_access], page: 1 }, other_user, other_account
    ).perform

    expect(result[:conversations]).to contain_exactly(other_conversation)
    expect(result[:conversations]).not_to include(one_failure)
  end

  it 'is offered to the dashboard as a conversation filter' do
    conversations = YAML.safe_load(Rails.root.join('lib/filters/filter_keys.yml').read)['conversations']

    expect(conversations['message_status']['filter_operators']).to eq(%w[equal_to not_equal_to])
  end
end
