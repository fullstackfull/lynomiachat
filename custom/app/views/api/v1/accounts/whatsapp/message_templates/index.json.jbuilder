json.payload do
  json.array! @templates do |template|
    json.partial! 'api/v1/accounts/whatsapp/message_templates/message_template',
                  template: template, context: @waba_contexts[template.business_account_id] || {}
  end
end

json.meta do
  # One entry per WhatsApp Business Account the account has connected: the inboxes on it, and when its templates were
  # last read from Meta. An account with none of these has no WhatsApp inbox yet, which is what the empty state says.
  json.whatsapp_business_accounts @waba_contexts.map do |waba_id, context|
    json.id waba_id
    json.inboxes context[:inboxes] || []
    json.last_synced_at context[:mirrored_at]&.to_i
  end
end
