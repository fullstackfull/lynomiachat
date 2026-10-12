# `message_count` and `attachment_count` for a whole page of tickets at once
# (docs/platform-support/12-refresh-against-product-refinement.md §2 "Ticket payload keys").
#
# WHY NOT A COUNTER CACHE OR A PER-ROW COUNT. A per-row count makes a list of 25 cost 50 extra queries, which
# is the N+1 the performance proof forbids; a counter-cache column would be two more columns to keep in step
# with a thread for a number no query filters on. Two grouped counts for the whole page is flat in the number
# of tickets, which is the property that matters.
#
# IT COUNTS PUBLIC MESSAGES AND THEIR ATTACHMENTS ONLY. Internal notes and their files are not in either number
# -- not filtered out, but never joined -- so the count cannot disclose that a note exists.
module PlatformSupport::ThreadTotals
  EMPTY = { messages: 0, attachments: 0 }.freeze

  module_function

  # Returns a hash keyed by ticket id. A ticket with an empty thread is absent from the grouped counts, so
  # callers read it through #for_ticket rather than assuming every id is present.
  def for_tickets(ticket_ids)
    ids = Array(ticket_ids)
    return {} if ids.empty?

    messages = PlatformSupport::Message.where(platform_support_ticket_id: ids)
                                       .group(:platform_support_ticket_id).count
    attachments = attachment_counts(ids)

    ids.index_with { |id| { messages: messages.fetch(id, 0), attachments: attachments.fetch(id, 0) } }
  end

  def for_ticket(totals, ticket_id)
    totals.fetch(ticket_id, EMPTY)
  end

  # Joined through the messages table so the result is grouped by TICKET rather than by message, which keeps
  # this one query for the whole page.
  def attachment_counts(ids)
    ActiveStorage::Attachment
      .where(record_type: PlatformSupport::Message.name,
             name: PlatformSupport::Message::FILES_ATTACHMENT_NAME)
      .joins('INNER JOIN platform_support_messages ' \
             'ON platform_support_messages.id = active_storage_attachments.record_id')
      .where(platform_support_messages: { platform_support_ticket_id: ids })
      .group('platform_support_messages.platform_support_ticket_id')
      .count
  end
end
