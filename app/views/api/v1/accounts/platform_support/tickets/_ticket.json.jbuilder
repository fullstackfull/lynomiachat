# One Platform Support ticket, as the customer sees it. Ids, enum values, counts and timestamps only: no
# message body, no provider payload, no credential, and nothing about a record the caller could not already
# read.
#
# THIS SERIALIZER IS DEFINED BY WHAT IT OMITS. Absent by construction, and none of them may be added without
# redoing the authorization review that removed them:
#
#   assignee_id, assignee_name              which operator holds the ticket is internal
#   the whole `sla` object, every *_due_at,
#   every *_breached_at, sla_paused_*       Lynomia's internal targets. The tenant helpdesk publishes its own
#                                           SLA object because there the commitment is the account's to itself;
#                                           here it is Lynomia's, and publishing it would turn an operational
#                                           goal into a contractual claim
#   plan_*_at_creation,
#   subscription_status_at_creation         commercial snapshots kept for operator analytics
#   internal_notes                          a different table this view has no association to
#   any blob URL                            blob URLs do not expire in this installation, so one in a JSON
#                                           response would be a permanent bearer token
#
# `unread` is derived from two columns rather than stored, so nothing has to be kept in step with the thread.
json.id ticket.id
json.reference ticket.reference
json.reference_number ticket.reference_number
json.subject ticket.subject
json.description ticket.description
json.category ticket.category
json.status ticket.status
json.priority ticket.priority
json.reporter_name ticket.reporter_name
json.unread ticket.unread?

# Counted for the whole page in one pair of queries, so a list of 25 does not cost 50 more.
totals = PlatformSupport::ThreadTotals.for_ticket(local_assigns.fetch(:totals, {}), ticket.id)
json.message_count totals[:messages]
json.attachment_count totals[:attachments]

json.last_activity_at ticket.last_activity_at.to_i
json.last_operator_message_at ticket.last_operator_message_at&.to_i
json.resolved_at ticket.resolved_at&.to_i
json.closed_at ticket.closed_at&.to_i
json.created_at ticket.created_at.to_i
json.updated_at ticket.updated_at.to_i
