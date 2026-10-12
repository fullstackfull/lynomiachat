# One contact's activity, in order, from every source that already records it
# (docs/p8/03-contact-activity-timeline.md).
#
# This is a READ PROJECTION, not a new event table. Every event it shows already has a canonical home -- a
# message, an activity message, a reporting event, a CSAT response, a campaign recipient, an automation
# execution, a flow session, a cart, an order action, a customer link. Writing them a second time into a
# timeline table would create a second source of truth that could disagree with the first, and would be empty
# for everything that happened before it existed.
#
# Composition rules:
#
#   * Each adapter is account-scoped and contact-scoped ON ITS OWN. No adapter relies on another having filtered
#     for it, so adding one cannot widen what an earlier one returned.
#
#   * Conversation-derived adapters read the conversations the caller may see, through
#     Conversations::PermissionFilterService -- the same filter the contact's attachment list already uses. An
#     agent restricted to some inboxes must not learn through a timeline what happened in a conversation they
#     cannot open.
#
#   * A CORE adapter failing is a failure. Messages and conversation events are what a contact timeline IS, so
#     if either cannot be read the request fails rather than quietly returning a timeline with the
#     communication missing. Every other adapter is OPTIONAL: it degrades to a warning plus `partial: true`,
#     because a commerce table being unavailable should not hide the conversation history.
#
#   * Pagination is mandatory and bounded. There is no unpaginated mode and no "all" limit.
class Contacts::ActivityTimelineQuery
  DEFAULT_LIMIT = 30
  MAX_LIMIT = 100

  # What each UI filter asks for. A category is a reading of the activity, not a table: `conversations` spans
  # activity messages, reporting events, CSAT and flow outcomes, because to an operator those are all "what
  # happened in the conversations".
  CATEGORIES = {
    messages: [Contacts::ActivityTimeline::MessagesAdapter],
    conversations: [
      Contacts::ActivityTimeline::ConversationEventsAdapter,
      Contacts::ActivityTimeline::ReportingEventsAdapter,
      Contacts::ActivityTimeline::CsatAdapter,
      Contacts::ActivityTimeline::FlowsAdapter
    ],
    campaigns: [Contacts::ActivityTimeline::CampaignsAdapter],
    automations: [Contacts::ActivityTimeline::AutomationsAdapter],
    commerce: [Contacts::ActivityTimeline::CommerceAdapter],
    tickets: [Contacts::ActivityTimeline::TicketsAdapter]
  }.freeze

  # The contact's own communication. If one of these cannot be read, the timeline is not partial -- it is wrong.
  CORE_ADAPTERS = [
    Contacts::ActivityTimeline::MessagesAdapter,
    Contacts::ActivityTimeline::ConversationEventsAdapter
  ].freeze

  # `page` groups the two pagination inputs, `cursor` and `limit`, because they are one concern and a caller
  # never sets one without thinking about the other.
  def initialize(account:, contact:, user:, categories: nil, page: {})
    @account = account
    @contact = contact
    @user = user
    @categories = resolve_categories(categories)
    @cursor = Contacts::ActivityTimeline::Cursor.decode(page[:cursor])
    @limit = resolve_limit(page[:limit])
    @warnings = []
  end

  def call
    entries = gather.sort_by(&:sort_key)
    page = entries.first(@limit)

    {
      payload: page.map(&:as_json),
      meta: {
        categories: @categories.map(&:to_s),
        limit: @limit,
        partial: @warnings.any?,
        warnings: @warnings,
        # More remains exactly when gathering limit + 1 from each adapter produced more than one page.
        next_cursor: entries.length > @limit ? Contacts::ActivityTimeline::Cursor.from_entry(page.last).encode : nil
      }.compact
    }
  end

  private

  def gather
    adapter_classes.flat_map do |klass|
      adapter = klass.new(account: @account, contact: @contact, visibility: visibility, cursor: @cursor)
      fetch_from(klass, adapter)
    end
  end

  # An optional adapter's failure is reported and skipped. A core adapter's failure is raised, and so is anything
  # that is not a database or adapter problem -- an authorization error must never be downgraded to a warning.
  def fetch_from(klass, adapter)
    adapter.fetch(@limit + 1)
  rescue ActiveRecord::ActiveRecordError, NoMethodError, KeyError => e
    raise if CORE_ADAPTERS.include?(klass)

    Rails.logger.error("Contact timeline adapter failed: #{klass.name} #{e.class.name}")
    @warnings << { scope: adapter.source, reason: 'unavailable' }
    []
  end

  def adapter_classes
    @categories.flat_map { |category| CATEGORIES.fetch(category) }.uniq
  end

  # Assembled once and shared by every adapter: who is asking, which of this contact's conversations they may
  # open, and which inboxes they may see.
  def visibility
    @visibility ||= Contacts::ActivityTimeline::Visibility.new(
      user: @user, conversations: visible_conversations, inbox_ids: visible_inbox_ids
    )
  end

  # The conversations of this contact that the caller may see. One query, shared by every adapter that needs it.
  def visible_conversations
    @visible_conversations ||= Conversations::PermissionFilterService.new(
      @account.conversations.where(contact_id: @contact.id), @user, @account
    ).perform
  end

  # The same permission rule as Conversations::PermissionFilterService, expressed over inboxes, for the sources
  # that carry an inbox but no conversation. Deriving it from this contact's conversations instead would hide a
  # campaign that addressed them in an inbox they have never written in.
  def visible_inbox_ids
    @visible_inbox_ids ||= if administrator?
                             @account.inboxes.select(:id)
                           else
                             @user.inboxes.where(account_id: @account.id).select(:id)
                           end
  end

  def administrator?
    AccountUser.find_by(account_id: @account.id, user_id: @user.id)&.administrator?
  end

  def resolve_categories(value)
    return CATEGORIES.keys if value.blank?

    requested = Array(value).map { |entry| entry.to_s.to_sym }
    unknown = requested - CATEGORIES.keys
    if unknown.any?
      raise CustomExceptions::Timeline::UnsupportedCategory.new(
        category: unknown.first.to_s, allowed: CATEGORIES.keys.map(&:to_s)
      )
    end

    requested.uniq
  end

  def resolve_limit(value)
    return DEFAULT_LIMIT if value.blank?

    limit = value.to_i
    raise CustomExceptions::Timeline::InvalidLimit.new(limit: value.to_s, maximum: MAX_LIMIT) unless limit.between?(1, MAX_LIMIT)

    limit
  end
end
