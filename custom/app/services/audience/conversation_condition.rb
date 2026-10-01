# Lynomia Audience: "the contact has a conversation where …" conditions for contact filters and audiences
# (docs/audience/02-audience-architecture.md). `equal_to` is "has at least one such conversation", `not_equal_to` "has
# none". Only conversations the user may see count (Conversations::PermissionFilterService, with the Enterprise custom-role
# rules), so a filter never reveals a conversation in an inbox the user cannot open; an automation rule, which has no
# user, evaluates a shared audience over the account's conversations.
class Audience::ConversationCondition
  OPERATORS = %w[equal_to not_equal_to].freeze
  FIELDS = {
    'conversation_status' => :status,
    'conversation_priority' => :priority,
    'conversation_inbox' => :inbox_id,
    'conversation_assignee' => :assignee_id,
    'conversation_team' => :team_id,
    'conversation_labels' => :labels
  }.freeze

  def initialize(key, account:, user:)
    @key = key
    @account = account
    @user = user
  end

  def operators = OPERATORS

  # SQL for the contacts query, and its bind values. `bind` is the condition's own bind name.
  def to_sql(operator, values, bind)
    conversations = accessible.where('conversations.contact_id = contacts.id')
    sql, binds = FIELDS.fetch(@key) == :labels ? labelled(conversations, values, bind) : [matching(conversations, values).select(1).to_sql, {}]
    ["#{'NOT ' if operator == 'not_equal_to'}EXISTS (#{sql})", binds]
  end

  private

  # Without a user (an automation rule evaluating a shared audience) the account's conversations count.
  def accessible
    return @account.conversations if @user.nil?

    Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform
  end

  def matching(conversations, values)
    column = FIELDS.fetch(@key)
    case column
    when :status then conversations.where(status: known(values, Conversation.statuses.keys))
    when :priority then conversations.where(priority: known(values, Conversation.priorities.keys))
    else conversations.where(column => values.map { |value| Integer(value.to_s, 10) })
    end
  rescue ArgumentError, TypeError
    invalid!
  end

  # Label names are the user's text, so they stay bind values of the outer query.
  def labelled(conversations, values, bind)
    invalid! unless values.all? { |value| value.is_a?(String) && value.length <= 255 }

    tagged = conversations.where(
      'EXISTS (SELECT 1 FROM taggings audience_taggings INNER JOIN tags audience_tags ON audience_tags.id = audience_taggings.tag_id ' \
      "WHERE audience_taggings.taggable_id = conversations.id AND audience_taggings.taggable_type = 'Conversation' " \
      "AND audience_tags.name IN (:#{bind}))"
    )
    [tagged.select(1).to_sql, { bind => values }]
  end

  def known(values, allowed)
    invalid! unless values.all? { |value| allowed.include?(value) }

    values
  end

  def invalid! = raise(CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: @key))
end
