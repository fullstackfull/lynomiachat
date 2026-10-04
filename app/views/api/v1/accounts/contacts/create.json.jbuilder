json.payload do
  json.contact do
    json.partial! 'api/v1/models/contact', formats: [:json], resource: @contact, with_contact_inboxes: true
    # What was actually persisted, so the caller never has to assume a label was applied. Only here and not in
    # the shared `_contact` partial: that one renders for every row of index, search and filter, where this
    # would cost a taggings query per contact.
    json.labels @contact.label_list
  end
  json.contact_inbox do
    json.inbox @contact_inbox&.inbox
    json.source_id @contact_inbox&.source_id
  end
end
