# Atomic dedup lock for WhatsApp incoming messages.
#
# Meta can deliver the same webhook event multiple times. This lock uses
# Redis SET NX EX to ensure only one worker processes a given source_id.
#
# It is a mutex, not a tombstone. Durable deduplication is the Message row itself, which
# `Whatsapp::IncomingMessageServiceHelpers#find_message_by_source_id` checks before anything else; this lock only
# serializes workers racing on the same id before that row exists. It therefore has to be released on every exit,
# including an exception — otherwise a single failed attempt (a media download timeout, a validation error) left
# the id locked for a day and every one of Meta's redeliveries was silently discarded, which is the one case where
# a customer message is lost with no trace anywhere.
class Whatsapp::MessageDedupLock
  KEY_PREFIX = Redis::RedisKeys::MESSAGE_SOURCE_KEY
  DEFAULT_TTL = 1.day.to_i

  def initialize(source_id, ttl: DEFAULT_TTL)
    @key = format(KEY_PREFIX, id: source_id)
    @ttl = ttl
  end

  # Returns true when the lock is acquired (caller should proceed).
  # Returns false when another worker already holds the lock.
  def acquire!
    ::Redis::Alfred.set(@key, true, nx: true, ex: @ttl)
  end

  # Always safe to call: deleting a key this worker no longer holds is a no-op, and the TTL remains the backstop
  # for a process that dies without reaching its ensure block.
  def release!
    ::Redis::Alfred.delete(@key)
  end
end
