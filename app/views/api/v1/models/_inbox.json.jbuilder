json.id resource.id
json.avatar_url resource.try(:avatar_url)
json.channel_id resource.channel_id
json.name resource.name
json.channel_type resource.channel_type
json.greeting_enabled resource.greeting_enabled
json.greeting_message resource.greeting_message
json.working_hours_enabled resource.working_hours_enabled
json.enable_email_collect resource.enable_email_collect
json.csat_survey_enabled resource.csat_survey_enabled
json.csat_config resource.csat_config
json.enable_auto_assignment resource.enable_auto_assignment
json.auto_assignment_config resource.auto_assignment_config
json.out_of_office_message resource.out_of_office_message
json.working_hours resource.weekly_schedule
json.timezone resource.timezone
json.callback_webhook_url resource.callback_webhook_url
json.allow_messages_after_resolved resource.allow_messages_after_resolved
json.lock_to_single_conversation resource.lock_to_single_conversation
json.sender_name_type resource.sender_name_type
json.business_name resource.business_name

if resource.portal.present?
  json.help_center do
    json.name resource.portal.name
    json.slug resource.portal.slug
  end
end

## Channel specific settings
## TODO : Clean up and move the attributes into channel sub section

json.tweets_enabled resource.channel.try(:tweets_enabled) if resource.twitter?
json.provider_name resource.channel.try(:provider_name) if resource.facebook? || resource.instagram? || resource.tiktok?

## WebWidget Attributes
json.allowed_domains resource.channel.try(:allowed_domains)
json.widget_color resource.channel.try(:widget_color)
json.website_url resource.channel.try(:website_url)
json.hmac_mandatory resource.channel.try(:hmac_mandatory)
json.welcome_title resource.channel.try(:welcome_title)
json.welcome_tagline resource.channel.try(:welcome_tagline)
json.web_widget_script resource.channel.try(:web_widget_script)
json.website_token resource.channel.try(:website_token)
json.selected_feature_flags resource.channel.try(:selected_feature_flags)
json.reply_time resource.channel.try(:reply_time)
if resource.web_widget?
  json.hmac_token resource.channel.try(:hmac_token) if Current.account_user&.administrator?
  json.pre_chat_form_enabled resource.channel.try(:pre_chat_form_enabled)
  json.pre_chat_form_options resource.channel.try(:pre_chat_form_options)
  json.continuity_via_email resource.channel.try(:continuity_via_email)
end

## Facebook Attributes
if resource.facebook?
  json.page_id resource.channel.try(:page_id)
  json.reauthorization_required resource.channel.try(:reauthorization_required?)
end

## Instagram Attributes
json.reauthorization_required resource.channel.try(:reauthorization_required?) if resource.instagram?
json.instagram_id resource.channel.try(:instagram_id) if resource.instagram?

## Tiktok Attributes
if resource.tiktok?
  json.business_id resource.channel.try(:business_id)
  json.reauthorization_required resource.channel.try(:reauthorization_required?)
end

## Twitter Attributes
json.profile_id resource.channel.try(:profile_id) if resource.twitter?

## LINE Attributes
json.line_channel_id resource.channel.try(:line_channel_id) if resource.channel_type == 'Channel::Line'

## Twilio Attributes
json.messaging_service_sid resource.channel.try(:messaging_service_sid)
json.phone_number resource.channel.try(:phone_number)
json.medium resource.channel.try(:medium) if resource.twilio?
if resource.twilio?
  json.content_templates resource.channel.try(:content_templates)
  if Current.account_user&.administrator?
    json.auth_token resource.channel.try(:auth_token)
    json.account_sid resource.channel.try(:account_sid)
    json.api_key_sid resource.channel.try(:api_key_sid)
  end
end

if resource.email?
  ## Email Channel Attributes
  json.email resource.channel.try(:email)
  # Lynomia (docs/p10/06-channel-lifecycle-health.md): `Inboxes::FetchImapEmailsJob` latches an authorization
  # error for ANY email channel, but this was reported only for Google and Microsoft inboxes and only to
  # administrators -- so a plain IMAP inbox whose password changed showed no warning anywhere, to anyone, which
  # is the common case on a self-hosted installation. A boolean is not a credential; the reconnect banners in
  # Settings.vue stay scoped to the OAuth providers that can act on it.
  json.reauthorization_required resource.channel.try(:reauthorization_required?)
  json.forwarding_enabled ENV.fetch('MAILER_INBOUND_EMAIL_DOMAIN', '').present?
  json.forward_to_email resource.channel.try(:forward_to_email) if ENV.fetch('MAILER_INBOUND_EMAIL_DOMAIN', '').present?
  if Current.account_user&.administrator? && defined?(with_branded_email_layout) && with_branded_email_layout.present? &&
     Current.account.feature_enabled?(:branded_email_templates)
    json.branded_email_layout resource.branded_email_layout
  end

  ## IMAP
  if Current.account_user&.administrator?
    json.imap_login resource.channel.try(:imap_login)
    json.imap_password resource.channel.try(:imap_password)
    json.imap_address resource.channel.try(:imap_address)
    json.imap_port resource.channel.try(:imap_port)
    json.imap_enabled resource.channel.try(:imap_enabled)
    json.imap_enable_ssl resource.channel.try(:imap_enable_ssl)
    json.imap_authentication resource.channel.try(:imap_authentication)

    # An OAuth inbox with no stored authorization at all is also waiting to be connected, which the latch alone
    # does not say. Overrides the general value above for exactly those inboxes.
    if resource.channel.try(:microsoft?) || resource.channel.try(:google?) || resource.channel.try(:legacy_google?)
      json.reauthorization_required resource.channel.try(:provider_config).empty? || resource.channel.try(:reauthorization_required?)
    end
  end

  ## SMTP
  if Current.account_user&.administrator?
    json.smtp_login resource.channel.try(:smtp_login)
    json.smtp_password resource.channel.try(:smtp_password)
    json.smtp_address resource.channel.try(:smtp_address)
    json.smtp_port resource.channel.try(:smtp_port)
    json.smtp_enabled resource.channel.try(:smtp_enabled)
    json.smtp_domain resource.channel.try(:smtp_domain)
    json.smtp_enable_ssl_tls resource.channel.try(:smtp_enable_ssl_tls)
    json.smtp_enable_starttls_auto resource.channel.try(:smtp_enable_starttls_auto)
    json.smtp_openssl_verify_mode resource.channel.try(:smtp_openssl_verify_mode)
    json.smtp_authentication resource.channel.try(:smtp_authentication)
  end
end

## API Channel Attributes
if resource.api?
  json.hmac_token resource.channel.try(:hmac_token) if Current.account_user&.administrator?
  json.secret resource.channel.try(:secret) if Current.account_user&.administrator?
  json.webhook_url resource.channel.try(:webhook_url)
  json.inbox_identifier resource.channel.try(:identifier)
  json.additional_attributes resource.channel.try(:additional_attributes)
end

json.provider resource.channel.try(:provider)

## Telegram Attributes
json.bot_name resource.channel.try(:bot_name) if resource.telegram?

### WhatsApp Channel
if resource.whatsapp?
  message_templates = resource.channel.try(:message_templates)
  json.message_templates message_templates.is_a?(Array) ? message_templates : []
  if Current.account_user&.administrator?
    json.provider_config resource.channel.provider_config.except(*Channel::Whatsapp::SECRET_PROVIDER_CONFIG_KEYS)
  end
  if Current.account_user&.administrator? &&
     ChatwootApp.chatwoot_cloud? &&
     (resource.channel.try(:provider_config) || {}).to_h['source'] == 'embedded_signup'
    json.business_management_token_configured resource.channel.try(:business_management_token).present?
  end
  # Lynomia (docs/p10/06-channel-lifecycle-health.md): this used to be reported only for embedded signup, on the
  # grounds that the manual flow uses API keys rather than OAuth. But `Channel::Whatsapp#setup_webhooks!` latches
  # reauthorization for BOTH providers, and an API key can be revoked just as an authorization can -- so a
  # manually configured number that could no longer authenticate showed no warning at all. The latch is now
  # reported whichever way the number was set up; `whatsappUnauthorized` in Settings.vue still gates the
  # reconnect flow on embedded signup, because that is the only flow that can complete it.
  json.reauthorization_required resource.channel.try(:reauthorization_required?)
end

## Voice attributes for TwilioSms
if resource.twilio? && resource.channel.respond_to?(:voice_enabled?)
  json.voice_enabled resource.channel.voice_enabled?
  json.inbound_calls_enabled resource.channel.inbound_calls_enabled?
  json.recording_enabled resource.channel.try(:recording_enabled?)
  json.transcription_enabled resource.channel.try(:transcription_enabled?)
  json.voice_configured resource.channel.try(:twiml_app_sid).present?
  json.has_api_key_secret resource.channel.try(:api_key_secret).present?
  if resource.channel.try(:twiml_app_sid).present?
    json.voice_call_webhook_url resource.channel.try(:voice_call_webhook_url)
    json.voice_status_webhook_url resource.channel.try(:voice_status_webhook_url)
  end
end

## Voice attribute for WhatsApp Cloud (only embedded-signup channels surface true)
if resource.channel_type == 'Channel::Whatsapp' && resource.channel.respond_to?(:voice_enabled?)
  json.voice_enabled resource.channel.voice_enabled?
  json.inbound_calls_enabled resource.channel.inbound_calls_enabled?
  json.recording_enabled resource.channel.try(:recording_enabled?)
  json.transcription_enabled resource.channel.try(:transcription_enabled?)
end

## Lynomia: one honest connection state per channel (docs/p10/06-channel-lifecycle-health.md).
## `reauthorization_required` above stays exactly as it is -- the existing UI reads it. This says the same thing
## for the channels that have no latch, and says `unknown` rather than nothing for the five that report no
## health at all. It is P9's Operations::Health::Component, not a second vocabulary.
json.connection_state Channels::ConnectionState.new(resource).call.as_json
