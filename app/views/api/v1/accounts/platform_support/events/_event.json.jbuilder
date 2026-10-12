# One customer-visible history entry.
#
# `metadata` is NEVER emitted -- there is no key for it here, so it cannot leak through an edit to this partial
# -- and `actor_name` is emitted only for the customer's own actions: what happened to the ticket is theirs to
# know, which operator did it is not.
json.id event.id
json.event_type event.event_type
json.actor_name event.customer_visible_actor_name
json.created_at event.created_at.to_i
