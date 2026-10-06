class Conversations::FilterService < FilterService
  ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

  def initialize(params, user, account)
    @account = account
    super(params, user)
  end

  def perform
    validate_query_operator
    @conversations = query_builder(@filters['conversations'])
    mine_count, unassigned_count, all_count, = set_count_for_all_conversations
    assigned_count = all_count - unassigned_count

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count
      }
    }
  end

  def base_relation
    # :messages is deliberately not preloaded: the list payload fetches messages through
    # scoped queries (last message, last_non_activity_message), which bypass the preload.
    conversations = @account.conversations.includes(
      :taggings, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team,
      :contact_inbox
    ).preload(
      inbox: :channel,
      ai_assignee: { avatar_attachment: [:blob] }
    )

    Conversations::PermissionFilterService.new(
      conversations,
      @user,
      @account,
      plan_hint_selective_filter: label_filter_present?
    ).perform
  end

  def current_page
    @params[:page] || 1
  end

  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  def conversations
    Conversations::SortService.apply(@conversations, @params[:sort_by]).page(current_page)
  end

  # `message_status` is not a column on conversations: it asks whether the conversation CONTAINS a message with
  # this status, which is the only way to find a conversation whose reply failed -- the failure is recorded on the
  # message, and conversations carry nothing that reflects it. Everything else still goes through the shared
  # column comparison.
  def handle_standard_attributes(current_filter, query_hash, current_index, filter_operator_value)
    return message_status_filter_query(query_hash, current_index) if message_status?(query_hash)

    super
  end

  # An unknown name maps to nil, so `IN (NULL)` matches nothing: a filter naming a status this version does not
  # have returns no conversations rather than every one of them.
  def filter_values(query_hash)
    return Array(query_hash['values']).map { |value| Message.statuses[value.to_s] } if message_status?(query_hash)

    super
  end

  private

  def message_status?(query_hash) = query_hash[:attribute_key].to_s == 'message_status'

  # Correlated rather than a join, so a conversation with several failed messages is returned once, and bounded by
  # `conversations.id` -- the leading column of index_messages_on_conversation_account_type_created.
  def message_status_filter_query(query_hash, current_index)
    @filter_values["value_#{current_index}"] = filter_values(query_hash)
    exists = "SELECT 1 FROM messages WHERE messages.conversation_id = #{filter_config[:table_name]}.id " \
             "AND messages.status IN (:value_#{current_index})"

    return "EXISTS (#{exists}) #{query_hash[:query_operator]}" if query_hash[:filter_operator] == 'equal_to'

    "NOT EXISTS (#{exists}) #{query_hash[:query_operator]}"
  end

  # The planner hint only pays off when the label condition positively narrows the
  # result set: `equal_to` joined by AND. Negative/presence operators or an OR in the
  # payload leave the result broad, where the inbox index is the better driver.
  def label_filter_present?
    payload = @params[:payload].to_a
    return false if payload.any? { |query_hash| query_hash[:query_operator].to_s.casecmp('or').zero? }

    payload.any? { |query_hash| query_hash[:attribute_key] == 'labels' && query_hash[:filter_operator] == 'equal_to' }
  end
end
