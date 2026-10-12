# Writes one row of a Platform Support ticket's history
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M6).
#
# ONE WRITER, because the alternative is a dozen call sites each deciding for itself what goes in `metadata` --
# and `metadata` is where the no-secrets rule has to hold. Callers pass ids, enum values, counts and timestamps;
# nothing here ever receives a message body, a provider payload or a credential, and `metadata` is never
# serialized to the tenant in any case.
#
# The actor is whoever acted: a tenant `User`, a `PlatformSupport::Agent`, or nothing at all for a machine
# event, which is recorded as `System`. The name is snapshotted through the same three-way `try` chain
# Custom::AuditLog uses on every audit row, so a history row stays attributable after the person's record is
# deleted and names a non-User actor rather than silently recording nobody.
class PlatformSupport::EventRecorder
  def initialize(ticket:, actor: nil)
    @ticket = ticket
    @actor = actor
  end

  def record(event_type, metadata: {})
    PlatformSupport::Event.create!(
      ticket: @ticket, event_type: event_type,
      actor_type: actor_type, actor_id: @actor&.id, actor_name: actor_name,
      metadata: metadata.compact.transform_keys(&:to_s)
    )
  end

  private

  # The allow-list is closed at the writer as well as in the model, and an actor of any other class raises
  # rather than being filed as a customer -- a wrong actor_type on a history row is a wrong answer, not a
  # cosmetic one, because the tenant serializer decides what to show from it.
  def actor_type
    case @actor
    when nil then PlatformSupport::Message::SYSTEM_AUTHOR_TYPE
    when PlatformSupport::Agent then PlatformSupport::Message::OPERATOR_AUTHOR_TYPE
    when ::User then PlatformSupport::Message::CUSTOMER_AUTHOR_TYPE
    else raise ArgumentError, "#{@actor.class.name} cannot act on a platform support ticket"
    end
  end

  def actor_name
    return nil if @actor.nil?

    @actor.try(:available_name).presence || @actor.try(:name).presence || @actor.class.name
  end
end
