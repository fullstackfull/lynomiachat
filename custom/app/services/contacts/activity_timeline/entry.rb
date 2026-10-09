# One row of a contact's activity timeline (docs/p8/03-contact-activity-timeline.md).
#
# Every adapter returns this shape, so the frontend learns one row contract rather than one per source. The
# fields are deliberately few: a stable id, what kind of thing happened, when, which conversation it belongs to,
# a short human summary and a small typed `meta` for the values a UI needs to render a chip or a link.
#
# `meta` carries ids, codes, counts and statuses only. It never carries a provider payload, a token, an
# encrypted value or a customer identifier the caller did not already have.
Contacts::ActivityTimeline::Entry = Data.define(:source, :record_id, :category, :kind, :occurred_at,
                                                :conversation_id, :summary, :meta) do
  # Long enough to recognise a message, short enough that a page of 50 is not a transcript dump. A singleton
  # method rather than a constant because Data.define's customization block cannot hold one.
  def self.summary_limit = 240

  # The optional fields carry defaults and the summary is truncated here, so no adapter has to remember either.
  def initialize(conversation_id: nil, summary: nil, meta: {}, **identity)
    super(
      conversation_id: conversation_id,
      summary: summary.presence && summary.to_s.truncate(self.class.summary_limit),
      meta: meta.compact,
      **identity.merge(source: identity.fetch(:source).to_s, category: identity.fetch(:category).to_s,
                       kind: identity.fetch(:kind).to_s)
    )
  end

  def id
    "#{source}:#{record_id}"
  end

  # Newest first, then by source and id so the order is total and a cursor can resume from any point. Without a
  # total order two rows at the same instant could swap between requests and one of them would be skipped or
  # repeated at a page boundary.
  def sort_key
    [-occurred_at.to_f, source, -record_id.to_i]
  end

  def as_json(*)
    {
      id: id, source: source, category: category, kind: kind,
      occurred_at: occurred_at.utc.iso8601(6), conversation_id: conversation_id,
      summary: summary, meta: meta
    }.compact
  end
end
