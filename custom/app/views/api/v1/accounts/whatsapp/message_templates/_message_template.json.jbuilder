# Facts, not sentences: the UI maps state + meta_status to its own copy (templateUtils.js), so the vocabulary lives in
# one place on the client and nothing here has to be translated. No credential is ever rendered -- the record holds
# none (docs/whatsapp-template-manager/02-local-record-design.md).
json.id template.id
json.name template.name
json.language template.language
json.category template.category
json.parameter_format template.parameter_format
json.components template.components
json.business_account_id template.business_account_id

# draft (Meta has never seen it) | submitting (handed over, no verdict yet) | remote (Meta owns its status now)
json.state template.local_state
json.meta_template_id template.meta_template_id
json.meta_status template.meta_status
# What Meta said, kept verbatim: the rejection enum, its human-readable explanation, the quality score, and the last
# event for the ones that are events rather than statuses (FLAGGED, LOCKED, REINSTATED, UNARCHIVED).
json.rejected_reason template.meta_payload['rejected_reason']
json.rejection_info template.meta_payload['rejection_info']
json.quality_score template.meta_payload['quality_score']
json.last_event template.meta_payload['last_event']

json.submitted_at template.submitted_at&.to_i
json.submission_error template.submission_error
json.last_seen_at template.meta_synced_at&.to_i
# Observed, not invented: the last sync of this WABA saw other templates and not this one.
json.missing_at_meta template.missing_at_meta?(context[:mirrored_at])

# A template belongs to a WABA, and several inboxes can share one, so this is a list.
json.inboxes context[:inboxes] || []
# Derived from Meta's current rules, server-side: the manager renders these and every lifecycle endpoint enforces them.
json.allowed_actions Whatsapp::Templates::Actions.new(template).all
# Meta's published rules, checked here so the builder can point at the input that is wrong before a submit costs a
# review cycle. Empty does not mean Meta will approve it -- only that nothing publicly documented is wrong.
json.validation_problems Whatsapp::Templates::Validator.new(template).problems

json.created_at template.created_at.to_i
json.updated_at template.updated_at.to_i
