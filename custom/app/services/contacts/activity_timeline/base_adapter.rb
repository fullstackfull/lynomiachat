# What every contact-timeline adapter shares (docs/p8/03-contact-activity-timeline.md).
#
# An adapter answers one question: "what did this source record for this contact, strictly before this cursor,
# newest first, at most `limit` rows". It is account-scoped and contact-scoped on its own, independently of every
# other adapter, so no adapter can rely on another having filtered for it.
#
# Conversation-derived adapters read `visible_conversations`, which is the same permission filter the contact's
# attachment list already uses (Conversations::PermissionFilterService). An agent restricted to some inboxes must
# not learn through a timeline what happened in a conversation they cannot open.
class Contacts::ActivityTimeline::BaseAdapter
  def initialize(account:, contact:, visible_conversations:, visible_inbox_ids:, cursor: nil)
    @account = account
    @contact = contact
    @visible_conversations = visible_conversations
    @visible_inbox_ids = visible_inbox_ids
    @cursor = cursor
  end

  # Subclasses implement #fetch(limit) and return an array of Contacts::ActivityTimeline::Entry.
  def fetch(_limit)
    raise NotImplementedError
  end

  def source
    self.class.name.demodulize.delete_suffix('Adapter').underscore
  end

  private

  # The cursor predicate for this adapter's own column, as SQL.
  #
  # Rows strictly older than the cursor instant always qualify. Rows at exactly that instant qualify only if they
  # come after the cursor in the total order (source ascending, then id descending) -- and because `source` is
  # constant within one adapter, that reduces to one of three cases, which is what this returns.
  def cursor_scope(scope, column, id_column: :id)
    return scope if @cursor.nil?

    table = scope.table_name
    older = "#{table}.#{column} < :instant"
    case @cursor.source <=> source
    when -1 then scope.where("#{older} OR #{table}.#{column} = :instant", instant: @cursor.occurred_at)
    when 0 then scope.where("#{older} OR (#{table}.#{column} = :instant AND #{table}.#{id_column} < :id)",
                            instant: @cursor.occurred_at, id: @cursor.record_id)
    else scope.where(older, instant: @cursor.occurred_at)
    end
  end

  # Conversations of this contact the current caller is allowed to see.
  def contact_conversations
    @visible_conversations
  end

  def conversation_ids
    @conversation_ids ||= contact_conversations.select(:id)
  end

  # The inboxes the caller may see, for the sources that carry an inbox but no conversation -- campaign
  # recipients above all. Derived from the caller's role by the query service, not from which conversations this
  # contact happens to have, because a campaign can address a contact in an inbox they have never written in.
  attr_reader :visible_inbox_ids
end
