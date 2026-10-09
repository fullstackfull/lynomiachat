# Every campaign that addressed this contact, and what became of it.
#
# `campaign_recipients` carries the contact directly and is the snapshot of who a campaign addressed, so this
# needs no join to reach the contact. It is still narrowed to the inboxes the caller may see, because a campaign
# sent through an inbox an agent has no access to is activity in that inbox.
#
# One row per recipient rather than one per state change: the ladder keeps only the furthest state reached and
# the per-state timestamps are on the same row, so `meta` carries them and the kind names where it got to. There
# is no per-transition history to expand into separate entries.
class Contacts::ActivityTimeline::CampaignsAdapter < Contacts::ActivityTimeline::BaseAdapter
  CATEGORY = 'campaigns'.freeze
  TIMESTAMP_COLUMNS = %i[sent_at delivered_at read_at failed_at].freeze

  def fetch(limit)
    rows(limit).map { |recipient| entry_for(recipient) }
  end

  private

  def rows(limit)
    scope = CampaignRecipient.where(account_id: @account.id, contact_id: @contact.id,
                                    inbox_id: visible_inbox_ids)
                             .includes(:campaign)
                             .reorder(created_at: :desc, id: :desc)
                             .limit(limit)
    cursor_scope(scope, :created_at)
  end

  def entry_for(recipient)
    Contacts::ActivityTimeline::Entry.new(
      source: source, record_id: recipient.id, category: CATEGORY,
      kind: "campaign_#{recipient.status}", occurred_at: recipient.created_at,
      meta: {
        campaign_id: recipient.campaign_id,
        campaign_title: recipient.campaign&.title,
        inbox_id: recipient.inbox_id,
        error_code: recipient.error_code,
        reason: recipient.error_message
      }.merge(ladder_timestamps(recipient))
    )
  end

  # The per-state timestamps the ladder stamped. They live on the one row, so a reader can see how far the send
  # got without a second request, and nothing has to be inferred from the status alone.
  def ladder_timestamps(recipient)
    TIMESTAMP_COLUMNS.index_with { |column| recipient.public_send(column)&.utc&.iso8601 }
  end
end
