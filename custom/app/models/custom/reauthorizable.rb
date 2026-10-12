# Lynomia Operations: make "this channel can no longer authenticate" durable
# (docs/p9/04-operations-center.md §recording).
#
# The OSS concern keeps the whole of a channel's broken state in Redis, under two keys with no TTL
# (app/models/concerns/reauthorizable.rb:20-72, lib/redis/redis_keys.rb:68-69). Nothing is written to Postgres,
# so "every broken inbox across all accounts, newest first" is not expressible, and a Redis flush silently turns
# a broken inbox green. This records the same two transitions as rows, beside the Redis flag rather than instead
# of it: the UI's `reauthorization_required?` keeps working exactly as before.
#
# Only the two STATE CHANGES are recorded, not every error. The concern already computes `state_changed` for
# both, so a channel failing once a minute produces one row that the recorder increments, not a row per poll.
#
# Reauthorizable is also included by AutomationRule and Integrations::Hook, which have no inbox. Those are
# skipped rather than recorded against a subject the operations console has no page for.
module Custom::Reauthorizable
  def prompt_reauthorization!
    was_required = reauthorization_required?
    super
    return if was_required

    operations_recorder&.record(
      :reauthorization_required, severity: :critical,
                                 reason: 'The channel reported an authorization error and needs to be reconnected',
                                 detail: { channel_type: self.class.name, attempts: authorization_error_count }
    )
  end

  def reauthorized!
    was_required = reauthorization_required?
    super
    operations_recorder&.resolve(:reauthorization_required) if was_required
  end

  private

  def operations_recorder
    return nil unless respond_to?(:inbox)

    channel_inbox = inbox
    return nil if channel_inbox.blank?

    Operations::SignalRecorder.new(source: :channel, account: channel_inbox.account, subject: channel_inbox)
  end
end
