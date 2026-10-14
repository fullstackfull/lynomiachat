# Draft, validate, publish and disable a flow bot's graph (docs/flow-builder/03-data-model-and-versioning.md).
#
#   draft      the bot's draft; created on first edit from the published graph (or a Start → End starter)
#   save!      replaces the draft's graph (shape checked; references are checked at publish), but only when the
#              caller's `lock_version` still matches the draft -- see Stale
#   validate   Flows::GraphValidator on the draft, against the bot's inboxes
#   publish!   the valid draft becomes the published version; the previous one is archived. Sessions keep the version
#              they started on; new sessions start on this one
#   disable!   archives the published version: no new session starts; live sessions are handed to humans
#   delete!    deletes a flow that is not published and has no live session (disable it first)
class Flows::Versions
  # SOMEBODY ELSE SAVED FIRST. Raised instead of overwriting their work: the caller edited a graph
  # that has since moved, so the only safe answers are "reload and reapply" or "discard mine", and
  # both of those are the editor's decision rather than this service's.
  class Stale < StandardError
    attr_reader :current

    def initialize(current)
      @current = current
      super('flow draft changed since it was loaded')
    end
  end

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

  # @param lock_version [Integer] the draft's lock_version as the caller loaded it. The comparison is the database's,
  #   not ours: assigning it makes ActiveRecord issue `UPDATE ... WHERE lock_version = ?`, so two saves racing on the
  #   same value cannot both win. A read-then-compare here would have a window between the read and the write.
  def save!(graph, lock_version:)
    errors = Flows::GraphValidator.new(@bot.account, graph).shape_errors
    raise Invalid, errors if errors.any?

    draft.tap do |version|
      version.lock_version = Integer(lock_version)
      version.update!(graph: graph)
      Flows::Audit.record('flow.updated', @bot, user: @user, changes: { version: version.version })
    rescue ActiveRecord::StaleObjectError
      raise Stale, version.reload
    end
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

  # No new session starts; live sessions are handed to humans (each under its conversation's lock).
  def disable!
    @bot.with_lock do
      published = @bot.published_flow_version
      next if published.nil?

      published.update!(status: :archived)
      Flows::Audit.record('flow.disabled', @bot, user: @user, changes: { version: published.version })
    end
    @bot.flow_sessions.live.pluck(:conversation_id).each { |id| Flows::RunJob.perform_later(id, 'disabled') }
  end

  def delete!
    @bot.with_lock do
      raise Invalid, [{ code: 'flow_active' }] if @bot.published_flow_version || @bot.flow_sessions.live.exists?

      Flows::Audit.record('flow.deleted', @bot, user: @user, changes: { name: @bot.name })
      @bot.destroy!
    end
  end

  private

  # THE LATEST VERSION, NOT ONLY THE PUBLISHED ONE.
  #
  # This read `@bot.published_flow_version&.graph || STARTER`, which is correct for a live flow and
  # silently destructive for a DISABLED one: disable! archives the published version, so a merchant
  # who turned a flow off and later reopened it got the two-node starter back and their flow was
  # gone from the editor. The rows were still there -- nothing was deleted -- but the next save
  # wrote a blank graph over the draft and publishing it replaced a working flow with an empty one.
  #
  # Ordering by `version` rather than by `created_at`: version is the sequence this service itself
  # assigns and the column the one-per-bot unique index is on, so it is total and gap-free, while
  # two versions created in the same transaction can share a timestamp.
  def create_draft
    base = (@bot.published_flow_version || @bot.flow_versions.order(version: :desc).first)&.graph || STARTER
    @bot.flow_versions.create!(account: @bot.account, version: (@bot.flow_versions.maximum(:version) || 0) + 1, graph: base,
                               created_by: @user)
  end
end
