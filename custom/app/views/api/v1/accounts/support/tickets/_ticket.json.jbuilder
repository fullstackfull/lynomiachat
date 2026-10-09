# One support case. Ids, enum values, counts and timestamps only: no message body, no provider payload, no
# credential, and nothing about a record the caller could not already read.
json.id ticket.id
json.reference ticket.reference
json.reference_number ticket.reference_number
json.title ticket.title
json.description ticket.description
json.category ticket.category
json.status ticket.status
json.priority ticket.priority
json.label_list ticket.label_list

json.conversation_id ticket.conversation_id
json.conversation_display_id ticket.conversation&.display_id
json.contact_id ticket.contact_id
json.inbox_id ticket.inbox_id
json.assignee_id ticket.assignee_id
json.team_id ticket.team_id
json.created_by_id ticket.created_by_id

json.source_type ticket.source_type
json.source_id ticket.source_id

json.sla do
  json.policy_id ticket.sla_policy_id
  json.applied ticket.sla_applied?
  json.paused ticket.sla_paused?
  json.paused_seconds ticket.sla_paused_seconds
  json.first_response_due_at ticket.first_response_due_at&.to_i
  json.resolution_due_at ticket.resolution_due_at&.to_i
  json.first_responded_at ticket.first_responded_at&.to_i
  json.first_response_breached_at ticket.first_response_breached_at&.to_i
  json.resolution_breached_at ticket.resolution_breached_at&.to_i
  json.breached ticket.breached?
end

json.last_activity_at ticket.last_activity_at.to_i
json.resolved_at ticket.resolved_at&.to_i
json.closed_at ticket.closed_at&.to_i
json.created_at ticket.created_at.to_i
json.updated_at ticket.updated_at.to_i
