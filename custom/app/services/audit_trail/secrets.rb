# The one definition of "this change describes a credential" (docs/p-final/clean-room/specs/A-audit-trail-read.md
# §5, docs/p-final/clean-room/specs/B-audit-event-capture.md §5).
#
# It is applied twice on purpose. Custom::AuditLog applies it on write, so no secret is ever stored; the trail's
# read surface applies it again, because rows written before this release are still in the table and the browser
# is where a leaked credential actually does harm. One module so the two can never drift.
#
# A matching key is DROPPED, not masked: a masked value still discloses a secret's length and shape, and a hash
# of one is still its fingerprint. An event whose only content was a credential changing is named through the
# record's `comment` instead.
module AuditTrail::Secrets
  # Matched on the key's name rather than on the value's shape. A name is a decision somebody made about what the
  # field holds; "this string looks like a token" is a guess that eventually throws away a customer's own data.
  KEY_PATTERN = /password|passwd|secret|token|api_key|apikey|credential|private_key|signature|verification_pin/i

  # How deep to walk a change value. A provider configuration is one hash deep; anything deeper is a payload
  # nobody should be auditing wholesale, so it is dropped rather than searched.
  MAX_DEPTH = 4

  # Walks the `{ column => [before, after] }` pairs the gem writes on an update as well as the flat
  # `{ column => value }` hashes it writes on create and destroy, so a nested provider credential is dropped
  # wherever in the structure it sits.
  def self.scrub(value, depth = MAX_DEPTH)
    case value
    when Hash then depth.positive? ? scrub_hash(value, depth) : nil
    when Array then value.map { |entry| scrub(entry, depth - 1) }
    else value
    end
  end

  def self.scrub_hash(hash, depth)
    hash.reject { |key, _value| secret_key?(key) }
        .transform_values { |nested| scrub(nested, depth - 1) }
  end

  def self.secret_key?(key)
    key.to_s.match?(KEY_PATTERN)
  end
end
