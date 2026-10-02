# Draft, validate and publish a flow bot's graph (docs/flow-builder/03-data-model-and-versioning.md).
#
#   draft      the bot's draft; created on first edit from the published graph (or a Start → End starter)
#   save!      replaces the draft's graph (shape checked; references are checked at publish)
#   validate   Flows::GraphValidator on the draft, against the bot's inboxes
#   publish!   the valid draft becomes the published version; the previous one is archived. Sessions keep the version
#              they started on; new sessions start on this one
class Flows::Versions
  class Invalid < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super('flow graph invalid')
    end
  end

  STARTER = {
    'nodes' => [
      { 'id' => 'start', 'type' => 'start', 'position' => { 'x' => 0, 'y' => 0 }, 'data' => {} },
      { 'id' => 'end', 'type' => 'end', 'position' => { 'x' => 0, 'y' => 200 }, 'data' => {} }
    ],
    'edges' => [{ 'id' => 'start-end', 'source' => 'start', 'sourceHandle' => 'next', 'target' => 'end' }]
  }.freeze

  def initialize(agent_bot, user: nil)
    @bot = agent_bot
    @user = user
  end

  def draft
    @bot.flow_versions.draft.first || @bot.with_lock { @bot.flow_versions.draft.first || create_draft }
  end

  def save!(graph)
    errors = Flows::GraphValidator.new(@bot.account, graph).shape_errors
    raise Invalid, errors if errors.any?

    draft.tap { |version| version.update!(graph: graph) }
  end

  def validate(version = draft) = Flows::GraphValidator.new(@bot.account, version.graph, inboxes: @bot.inboxes.to_a).errors

  def publish!
    @bot.with_lock do
      version = draft
      errors = validate(version)
      raise Invalid, errors if errors.any?

      @bot.flow_versions.published.update_all(status: FlowVersion.statuses[:archived], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      version.update!(status: :published, published_at: Time.current, published_by: @user)
      Flows::Audit.record('flow.published', @bot, user: @user, changes: { version: version.version })
      version
    end
  end

  private

  def create_draft
    base = @bot.published_flow_version&.graph || STARTER
    @bot.flow_versions.create!(account: @bot.account, version: (@bot.flow_versions.maximum(:version) || 0) + 1, graph: base,
                               created_by: @user)
  end
end
