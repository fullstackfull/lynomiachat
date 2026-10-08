# Lynomia keeps Chatwoot's audit row for a channel configuration change after the Enterprise overlay goes. The OSS
# concern still declares `after_update :create_audit_log_entry` (app/models/concerns/channelable.rb:7) and still
# leaves the body empty (:10), with `Channelable.prepend_mod_with('Channelable')` live at :13 -- so this is the
# missing half of an extension point that was already wired, not a new mechanism.
#
# ONE DELIBERATE DIFFERENCE from the implementation this replaces, and it is a security fix rather than a port.
# Enterprise audited `saved_changes.except('updated_at', 'secret')`, which excluded exactly one credential column --
# `secret`, which only `channel_api` has. Every other channel credential went into `audits.audited_changes` in
# plaintext, BOTH the old value and the new one, and the reader renders that payload verbatim to any administrator
# of the account (custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder). Across the twelve models that
# include Channelable that is `imap_password`, `smtp_password`, `user_access_token`, `page_access_token`,
# `access_token`, `refresh_token`, `line_channel_secret`, `line_channel_token`, `bot_token`, `auth_token`,
# `api_key_sid`, `api_key_secret`, `twitter_access_token`, `twitter_access_token_secret`, `website_token`,
# `hmac_token`, `business_management_token`, and the `provider_config` blob that carries the WhatsApp `api_key`.
#
# So the value is replaced and the key is kept: where a row is written at all, the audit records THAT a credential
# changed, and by whom, without becoming a place to read it from.
#
# Everything else is the original behaviour, including which changes write a row at all -- and that has one
# consequence worth naming rather than discovering later. `secret` is `except`-ed, not filtered, so a change to it
# ALONE leaves the hash blank and writes nothing. `POST .../inboxes/:id/reset_secret`
# (app/controllers/api/v1/accounts/concerns/inbox_secret_management.rb:4) does exactly that: rotating a Channel::Api
# webhook signing secret is unaudited. That was true before the overlay was removed and is preserved here on
# purpose, because which changes trigger a row is behaviour this relocation was asked not to alter. Auditing it is a
# product change, not a port.
module Custom::Channelable
  extend ActiveSupport::Concern

  # Rails' own parameter filtering uses this marker, so it reads as redaction rather than as a stored value.
  FILTERED = '[FILTERED]'.freeze

  # An attribute whose name carries one of these never has its value recorded. Checked against every column of all
  # twelve Channelable models rather than guessed. `hmac_mandatory` and `smtp_authentication` deliberately do not
  # match, because they are a policy boolean and an auth *method* name, both worth auditing. It over-matches once,
  # on `channel_tiktok.refresh_token_expires_at`: a timestamp, filtered because it carries `token`. Left as is --
  # over-filtering a refresh deadline costs nothing, and narrowing the regex to spare it would be the kind of
  # special case that later lets a real credential through.
  CREDENTIAL_NAME = /token|secret|password|key|credential|signature/i

  # The one credential-bearing jsonb column on these models, named because its name matches nothing above: it is
  # where the WhatsApp `api_key` lives, and it exists on the email, sms, twilio_sms and whatsapp channels.
  #
  # Deliberately NOT a blanket rule over every structured value. Five of the nine jsonb columns on these twelve
  # tables hold no credential and are exactly what an administrator changes and would later want to read back:
  # `channel_api.additional_attributes` (`agent_reply_time_window`, in that model's EDITABLE_ATTRS),
  # `channel_web_widgets.pre_chat_form_options` (the pre-chat form's fields, likewise editable),
  # `channel_whatsapp.message_templates`, `channel_twilio_sms.content_templates` and
  # `channel_whatsapp.phone_number_health`. Redacting those would say an inbox changed without saying what
  # changed, which is the audit row's whole purpose, and would lose it with no security gained.
  CREDENTIAL_BLOBS = %w[provider_config].freeze

  # ActiveSupport::Concern's `included` reorders the method lookup chain, so the instance methods are prepended
  # explicitly to sit ahead of the OSS no-op. Same manual prepend as the implementation this replaces.
  # https://stackoverflow.com/q/40061982/3824876
  included do
    prepend InstanceMethods
  end

  module InstanceMethods
    def create_audit_log_entry
      return if inbox.nil?

      # `.except('updated_at', 'secret')` decides both whether a row is written and what it says, exactly as before:
      # a change to `secret` alone still leaves the hash blank and writes nothing.
      audited_changes = saved_changes.except('updated_at', 'secret')

      return if audited_changes.blank?
      return if messaging_template_updates?(audited_changes)

      Custom::AuditLog.create(
        auditable_id: inbox.id,
        auditable_type: 'Inbox',
        action: 'update',
        associated_id: account.id,
        associated_type: 'Account',
        audited_changes: filter_credentials(audited_changes)
      )
    end

    def messaging_template_updates?(changes)
      # if there is more than one key, return false
      return false unless changes.keys.length == 1

      # if the only key is message_templates_last_updated, return true
      changes.key?('message_templates_last_updated')
    end

    private

    # Keeps the key and the `[before, after]` shape, so the reader and its `audited_changes` rendering are unchanged.
    # `provider_config` is filtered whole rather than key by key: it is a credential blob, and filtering inside it
    # would mean tracking which of a provider's keys are secret, in a hash this installation does not define.
    def filter_credentials(changes)
      changes.to_h do |attribute, values|
        [attribute, filter_attribute?(attribute) ? values.map { FILTERED } : values]
      end
    end

    def filter_attribute?(attribute)
      CREDENTIAL_NAME.match?(attribute) || CREDENTIAL_BLOBS.include?(attribute)
    end
  end
end
