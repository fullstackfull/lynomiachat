class Webhooks::WhatsappEventsJob < MutexApplicationJob
  queue_as :low
  # Retry budget (19 × 2s = 38s) must exceed the 30s lock TTL set in `perform`, otherwise
  # a webhook that arrives just after the lock is acquired can exhaust retries before the
  # holder finishes and silently drop its message.
  retry_on LockAcquisitionError, wait: 2.seconds, attempts: 20

  def perform(params = {})
    channel = find_channel_from_whatsapp_business_payload(params)

    return unless ingestible?(channel, params)

    sender_id = contact_sender_id(params)
    return process_events(channel, params) if sender_id.blank?

    # Album uploads arrive as separate concurrent webhooks. Serialize per (inbox, contact)
    # so the first webhook creates the conversation and the rest append to it.
    # 30s TTL covers the attachment download + transaction — the default 1s expires
    # mid-processing and lets a concurrent webhook re-acquire before the first commit.
    key = format(::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: sender_id)
    with_lock(key, 30.seconds) do
      process_events(channel, params, sender_id)
    end
  end

  def process_events(channel, params, locked_sender_id = nil)
    if message_echo_event?(params)
      handle_message_echo(channel, params)
    else
      handle_message_events(channel, params, locked_sender_id)
    end
  end

  # Detects if the webhook is an SMB message echo event (message sent from WhatsApp Business app)
  # This is part of WhatsApp coexistence feature where businesses can respond from both
  # Chatwoot and the WhatsApp Business app, with messages synced to Chatwoot.
  #
  # Regular message payload (field: "messages"):
  # {
  #   "entry": [{
  #     "changes": [{
  #       "field": "messages",
  #       "value": {
  #         "contacts": [{ "wa_id": "919745786257", "profile": { "name": "Customer" } }],
  #         "messages": [{ "from": "919745786257", "id": "wamid...", "text": { "body": "Hello" } }]
  #       }
  #     }]
  #   }]
  # }
  #
  # Echo message payload (field: "smb_message_echoes"):
  # {
  #   "entry": [{
  #     "changes": [{
  #       "field": "smb_message_echoes",
  #       "value": {
  #         "contacts": [{
  #           "wa_id": "919745786257", "user_id": "IN.2081978709342942",
  #           "parent_user_id": "IN.ENT.11815799212886844830"
  #         }],
  #         "message_echoes": [{
  #           "from": "971545296927", "to": "919745786257", "to_user_id": "IN.2081978709342942",
  #           "to_parent_user_id": "IN.ENT.11815799212886844830",
  #           "id": "wamid...", "text": { "body": "Hi" }
  #         }]
  #       }
  #     }]
  #   }]
  # }
  #
  # Key differences:
  # - field: "smb_message_echoes" instead of "messages"
  # - message_echoes[] instead of messages[]
  # - "from" is the business number; "to" is the contact phone and can be omitted
  # - "to_user_id" is the contact BSUID; "to_parent_user_id" is included when parent BSUIDs are enabled
  # - contacts[] contains the same contact identifiers
  def message_echo_event?(params)
    params.dig(:entry, 0, :changes, 0, :field) == 'smb_message_echoes'
  end

  def handle_message_echo(channel, params)
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params, outgoing_echo: true).perform
  end

  def handle_message_events(channel, params, locked_sender_id = nil)
    case channel.provider
    when 'whatsapp_cloud'
      service_params = { inbox: channel.inbox, params: params }
      service_params[:locked_sender_id] = locked_sender_id if locked_sender_id.present?
      Whatsapp::IncomingMessageWhatsappCloudService.new(**service_params).perform
    else
      Whatsapp::IncomingMessageService.new(inbox: channel.inbox, params: params).perform
    end
  end

  private

  # Echo payloads reverse the fields — `from` is the business number and `to` is the contact.
  # Returns nil for status-only webhooks so they bypass the lock.
  def contact_sender_id(params)
    value = params.dig(:entry, 0, :changes, 0, :value) || params
    return contact_sender_id_from_message_echoes(value[:message_echoes]) if value[:message_echoes].present?

    contact_sender_id_from_messages(value[:messages], value[:contacts])
  end

  # Echo payloads are outbound messages from the WhatsApp Business app, so `to`
  # points to the contact. Prefer parent BSUID when present so payloads that have
  # both regular+parent BSUIDs serialize with parent-BSUID-only payloads.
  def contact_sender_id_from_message_echoes(message_echoes)
    message = message_echoes&.first
    return if message.blank?

    [message[:to_parent_user_id], message[:to_user_id], message[:to]].compact_blank.first
  end

  # Regular inbound payloads are sent by the contact, so `from` points to the
  # contact. Prefer parent BSUID when present so payloads that have both
  # regular+parent BSUIDs serialize with parent-BSUID-only payloads.
  def contact_sender_id_from_messages(messages, contacts)
    message = messages&.first
    return if message.blank?
    return contact_sender_id_from_system_message(message) if message[:type] == 'system'

    contact = contacts&.first || {}

    [
      message[:from_parent_user_id],
      contact[:parent_user_id],
      message[:from_user_id],
      contact[:user_id],
      message[:from]
    ].compact_blank.first
  end

  # Identity changes arrive on the existing messages subscription as system messages. Lock on
  # the newly introduced identity so the lifecycle event serializes with the first inbound
  # message that uses it. The rotation service acquires the remaining current-identifier locks.
  def contact_sender_id_from_system_message(message)
    system = message[:system] || {}

    [system[:parent_user_id], system[:user_id], system[:wa_id], message[:from]].compact_blank.first
  end

  # Whether this payload can be ingested at all, and a truthful operational record when it cannot.
  #
  # This used to also refuse a channel whose `reauthorization_required?` flag was set, for an embedded-signup
  # source. That dropped every inbound customer message for the channel — permanently, since the flag has no
  # expiry — while outbound kept working, and it did so after the controller had already answered Meta 200 OK, so
  # Meta never retried and Sidekiq recorded a success.
  #
  # It protected nothing. Meta delivers these payloads to us: resolving a Contact, a Conversation and a Message is
  # entirely local and needs no Meta credential. The only inbound step that does is the media download, and
  # `Whatsapp::IncomingMessageBaseService#attach_files` already returns early when the download fails and still
  # saves the message — an attachment-less message is a supported state, not a broken one. So a channel awaiting
  # reauthorization now ingests, and loses at most its attachments.
  #
  # The two refusals that remain are the ones where there is genuinely nothing to write to. Neither is retryable:
  # a payload naming a phone_number_id this installation does not own will never become ingestible, and retrying
  # would only repeat the drop. Both are therefore reported rather than retried.
  def ingestible?(channel, params)
    return report_unroutable(params) if channel.blank?
    return report_inactive_account(channel) unless channel.account.active?

    true
  end

  # No channel matches the payload's phone_number_id. Resolution depends entirely on a strict match against
  # `provider_config['phone_number_id']`, so this is usually a stale or mistyped id on the channel, or a number
  # that belongs to another installation sharing the Meta app.
  def report_unroutable(params)
    metadata = whatsapp_business_metadata(params)
    log_ingest_failure(
      'unroutable_payload',
      phone_number_id: metadata[:phone_number_id],
      url_phone_number: params[:phone_number],
      detail: 'no Channel::Whatsapp has this phone_number_id in provider_config'
    )
    false
  end

  def report_inactive_account(channel)
    log_ingest_failure(
      'inactive_account',
      channel_id: channel.id,
      inbox_id: channel.inbox&.id,
      account_id: channel.account_id,
      phone_number_id: channel.provider_config['phone_number_id'],
      detail: 'the account is not active, so inbound is not ingested'
    )
    false
  end

  # One structured line per dropped inbound payload, because a permanently discarded customer message must not be
  # visible only as a bare warning. No token, no secret, no message body — the fields are what an operator needs
  # to find the channel and the Meta-side record.
  def log_ingest_failure(event, **fields)
    Rails.logger.error(
      "[WHATSAPP INGEST] event=#{event} #{fields.compact.map { |key, value| "#{key}=#{value}" }.join(' ')}"
    )
  end

  def find_channel_by_url_param(params)
    return unless params[:phone_number]

    Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  end

  # For a Cloud API delivery the payload's own metadata is the ONLY acceptable source, and the URL segment is
  # deliberately not consulted — not even as a fallback.
  #
  # An audit flagged `find_channel_by_url_param` as unreachable here and suggested reviving it. That is wrong, and
  # `spec/jobs/webhooks/whatsapp_events_job_spec.rb:44` already pins why: one Meta app serves many numbers
  # (chatwoot/chatwoot#4712), and the URL is whatever the phone-level callback override was registered with. If the
  # metadata names a number this installation does not own, falling back to the URL would file that customer's
  # message under a DIFFERENT channel's inbox — a cross-number misattribution. Refusing the payload and saying so
  # loudly is the correct behaviour; `report_unroutable` is what makes it visible.
  #
  # The URL lookup stays reachable for providers that post a different payload shape to the per-number route
  # (360dialog, `provider == 'default'`), which is the branch below.
  def find_channel_from_whatsapp_business_payload(params)
    return get_channel_from_wb_payload(params) if params[:object] == 'whatsapp_business_account'

    find_channel_by_url_param(params)
  end

  def whatsapp_business_metadata(params)
    return {} unless params[:object] == 'whatsapp_business_account'

    params[:entry]&.first&.dig(:changes)&.first&.dig(:value, :metadata) || {}
  end

  def get_channel_from_wb_payload(wb_params)
    metadata = whatsapp_business_metadata(wb_params)
    Whatsapp::WebhookChannelFinderService.new(
      display_phone_number: metadata[:display_phone_number],
      phone_number_id: metadata[:phone_number_id]
    ).perform
  end
end

Webhooks::WhatsappEventsJob.prepend_mod_with('Webhooks::WhatsappEventsJob')
