# One history entry. `data` holds only the ids, enum values and timestamps the recorder put there; `body` is
# populated for a note and nil for everything else.
json.id event.id
json.event_type event.event_type
json.body event.body
json.data event.data
json.user_id event.user_id
json.user_name event.user&.available_name
json.created_at event.created_at.to_i
