# The opaque position in a contact's activity timeline (docs/p8/03-contact-activity-timeline.md).
#
# It encodes the full sort key -- instant, source, record id -- because the order is total and anything less
# would skip or repeat a row where two sources recorded something in the same instant.
#
# It is an encoded string rather than three query parameters so a caller cannot build a half-valid position, and
# a malformed one is refused at the boundary with 422 rather than producing a silently wrong page.
class Contacts::ActivityTimeline::Cursor
  SEPARATOR = '|'.freeze

  attr_reader :occurred_at, :source, :record_id

  def self.from_entry(entry)
    new(occurred_at: entry.occurred_at, source: entry.source, record_id: entry.record_id)
  end

  def self.decode(value)
    return nil if value.blank?

    parts = Base64.urlsafe_decode64(value.to_s).split(SEPARATOR, 3)
    raise CustomExceptions::Timeline::InvalidCursor.new(cursor: value.to_s) unless parts.length == 3

    new(occurred_at: Time.zone.parse(parts[0]), source: parts[1], record_id: parts[2])
  rescue ArgumentError, TypeError
    raise CustomExceptions::Timeline::InvalidCursor.new(cursor: value.to_s)
  end

  def initialize(occurred_at:, source:, record_id:)
    raise CustomExceptions::Timeline::InvalidCursor.new(cursor: 'blank') if occurred_at.blank?

    @occurred_at = occurred_at
    @source = source.to_s
    @record_id = record_id.to_s
  end

  def encode
    Base64.urlsafe_encode64([@occurred_at.utc.iso8601(6), @source, @record_id].join(SEPARATOR))
  end
end
