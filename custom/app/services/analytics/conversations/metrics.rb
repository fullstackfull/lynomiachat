# Lynomia Analytics: the conversation and message metrics behind the overview screen
# (docs/p8/02a-overview-conversation-analytics.md).
#
# Two kinds of number live here and they are never mixed:
#
#   EVENT metrics are things that happened, counted inside the requested range. They come from
#   `reporting_events` or from `created_at` on the row itself, and they are bucketable over time.
#
#   CURRENT STATE metrics describe how things stand right now. `unresolved_backlog` is the only one, and it is
#   deliberately NOT date-filtered: a backlog is a reading taken at an instant, and the instant is now. There is
#   no honest way to produce "backlog as it stood last Tuesday" from this schema, because conversations keep only
#   their current status and the single most recent `status_changed_at` -- no per-transition history exists
#   (docs/p8/00-discovery.md §3). The response labels the kind so a chart cannot present one as the other.
#
# Every query is scoped to the account passed in, which the controller takes from Current.account.
class Analytics::Conversations::Metrics
  EVENT_METRICS = %i[
    conversations_created conversations_resolved conversations_reopened
    avg_first_response_time avg_resolution_time inbound_messages outbound_messages
  ].freeze
  CURRENT_STATE_METRICS = %i[unresolved_backlog].freeze

  # Chatwoot keeps unresolved work in these two statuses. `snoozed` is excluded because a snoozed conversation is
  # deliberately out of the queue until it wakes, so counting it as backlog would overstate what an agent faces.
  BACKLOG_STATUSES = %i[open pending].freeze

  def initialize(account:, date_range:, filters:)
    @account = account
    @date_range = date_range
    @filters = filters
  end

  def conversations_created
    filtered_conversations.where(created_at: @date_range.utc_range).count
  end

  def conversations_resolved
    reporting_events('conversation_resolved').count
  end

  # A `conversation_opened` row records both a first open and a reopen. The listener distinguishes them by what it
  # writes into event_start_time: for a first open it is the conversation's own created_at, and for a reopen it is
  # the end of the resolution that preceded it (app/listeners/reporting_event_listener.rb:101-124). So comparing
  # the two columns is the discriminator the writer itself established, and it holds for any number of cycles --
  # resolved -> reopened -> resolved -> reopened produces one row per reopen, each with a start time taken from
  # its own preceding resolution.
  #
  # `value > 0` would be the obvious shortcut and is wrong: a conversation reopened inside the same second as its
  # resolution has value 0 and would be counted as a creation.
  def conversations_reopened
    reporting_events('conversation_opened')
      .joins(:conversation)
      .where.not('reporting_events.event_start_time = conversations.created_at')
      .count
  end

  def avg_first_response_time
    average_duration('first_response')
  end

  def avg_resolution_time
    average_duration('conversation_resolved')
  end

  def inbound_messages
    chat_messages.where(message_type: :incoming).count
  end

  def outbound_messages
    chat_messages.where(message_type: :outgoing).count
  end

  # Current state, not a count over the range.
  def unresolved_backlog
    filtered_conversations.where(status: BACKLOG_STATUSES).count
  end

  # Series are emitted for every bucket in the range including the zeros, so a chart never has to infer a gap.
  # Grouping is done in SQL in the account's timezone by groupdate, the same mechanism the existing v2 report
  # builders use (app/builders/v2/report_builder.rb:103-111).
  def series(metric)
    counts = case metric
             when :conversations_created then bucketed(filtered_conversations.where(created_at: @date_range.utc_range), 'conversations.created_at')
             when :conversations_resolved then bucketed(reporting_events('conversation_resolved'), 'reporting_events.created_at')
             when :inbound_messages then bucketed(chat_messages.where(message_type: :incoming), 'messages.created_at')
             when :outbound_messages then bucketed(chat_messages.where(message_type: :outgoing), 'messages.created_at')
             end
    fill_buckets(counts)
  end

  def breakdown(dimension)
    case dimension
    when :inbox then rows_for(filtered_conversations.group(:inbox_id), inbox_labels)
    when :channel then channel_rows
    when :team then rows_for(filtered_conversations.where.not(team_id: nil).group(:team_id), team_labels)
    when :agent then rows_for(filtered_conversations.where.not(assignee_id: nil).group(:assignee_id), agent_labels)
    end
  end

  private

  # Account scope first, then the shared filters. Every filter id was already proved to belong to this account by
  # Analytics::FilterSet before it reached here.
  def filtered_conversations
    scope = @account.conversations
    scope = scope.where(inbox_id: @filters[:inbox_id]) if @filters[:inbox_id]
    scope = scope.where(team_id: @filters[:team_id]) if @filters[:team_id]
    scope = scope.where(assignee_id: @filters[:agent_id]) if @filters[:agent_id]
    scope = scope.where(inbox_id: channel_inbox_ids) if @filters[:channel_type]
    scope
  end

  # `Message.chat` is the repository's own definition of real communication: not an activity row and not private
  # (app/models/message.rb:119). System templates -- greeting, out-of-office, CSAT, email collect -- carry
  # message_type `template` and are excluded by filtering to incoming/outgoing, because they are product
  # messaging rather than an exchange with the customer. A WhatsApp approved template send is an ordinary
  # `outgoing` message and is therefore counted.
  def chat_messages
    scope = @account.messages.chat.where(created_at: @date_range.utc_range)
    scope = scope.where(inbox_id: @filters[:inbox_id]) if @filters[:inbox_id]
    scope = scope.where(inbox_id: channel_inbox_ids) if @filters[:channel_type]
    scope = scope.where(conversation_id: filtered_conversations.select(:id)) if @filters[:team_id] || @filters[:agent_id]
    scope.unscope(:order)
  end

  def reporting_events(name)
    scope = ReportingEvent.where(account_id: @account.id, name: name, created_at: @date_range.utc_range)
    scope = scope.where(inbox_id: @filters[:inbox_id]) if @filters[:inbox_id]
    scope = scope.where(inbox_id: channel_inbox_ids) if @filters[:channel_type]
    scope = scope.where(user_id: @filters[:agent_id]) if @filters[:agent_id]
    scope = scope.where(conversation_id: filtered_conversations.select(:id)) if @filters[:team_id]
    scope
  end

  # Returns nil rather than 0 when there is nothing to average, so "no conversations were resolved" is not
  # displayed as "resolved instantly".
  def average_duration(name)
    reporting_events(name).average(:value)&.to_f
  end

  def bucketed(scope, column)
    scope.group_by_period(@date_range.group_by, Arel.sql(column), time_zone: @date_range.zone, default_value: 0).count
  end

  def fill_buckets(counts)
    normalized = (counts || {}).transform_keys { |key| key.to_date.strftime(Analytics::DateRange::DATE_FORMAT) }
    @date_range.bucket_starts.map do |bucket|
      key = bucket.to_date.strftime(Analytics::DateRange::DATE_FORMAT)
      { bucket: key, value: normalized[key].to_i }
    end
  end

  def rows_for(grouped_scope, labels)
    grouped_scope.count.sort_by { |_id, count| -count }.map do |id, count|
      { id: id, label: labels[id] || "##{id}", value: count }
    end
  end

  # Channel is a property of the inbox, not of the conversation, so the breakdown groups through the join rather
  # than pretending conversations carry a channel column.
  def channel_rows
    filtered_conversations.joins(:inbox).group('inboxes.channel_type').count
                          .sort_by { |_type, count| -count }
                          .map { |type, count| { id: type, label: type.to_s.delete_prefix('Channel::'), value: count } }
  end

  def channel_inbox_ids
    @channel_inbox_ids ||= @account.inboxes.where(channel_type: @filters[:channel_type]).select(:id)
  end

  def inbox_labels
    @inbox_labels ||= @account.inboxes.pluck(:id, :name).to_h
  end

  def team_labels
    @team_labels ||= @account.teams.pluck(:id, :name).to_h
  end

  def agent_labels
    @agent_labels ||= User.where(id: @account.account_users.select(:user_id)).pluck(:id, :name).to_h
  end
end
