json.partial! 'api/v1/accounts/whatsapp/message_templates/message_template',
              template: @template, context: @waba_contexts[@template.business_account_id] || {}
