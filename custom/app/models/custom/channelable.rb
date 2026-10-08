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
# So the value is replaced and the key is kept: the audit still records THAT a credential was rotated, and by whom,
# without becoming a place to read it from. Everything else is the original behaviour, including which changes write
# a row at all.
module Custom::Channelable
  extend ActiveSupport::Concern

  # Rails' own parameter filtering uses this marker, so it reads as redaction rather than as a stored value.
  FILTERED = '[FILTERED]'.freeze

  # An attribute whose name carries one of these never has its value recorded. Checked against every column of all
  # twelve Channelable models rather than guessed; `hmac_mandatory` and `smtp_authentication` deliberately do not
  # match, because they are a policy boolean and an auth *method* name, both worth auditing.
  CREDENTIAL_NAME = /token|secret|password|key|credential|signature/i

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
    def filter_credentials(changes)
      changes.to_h do |attribute, values|
        [attribute, filter_attribute?(attribute, values) ? values.map { FILTERED } : values]
      end
    end

    # A structured value is filtered whole: every jsonb column on these models is a provider configuration blob, and
    # `provider_config` is where the WhatsApp `api_key` lives. Default-deny, so a key an upstream release adds to one
    # of those blobs is redacted rather than leaked.
    def filter_attribute?(attribute, values)
      CREDENTIAL_NAME.match?(attribute) || values.any? { |value| value.is_a?(Hash) || value.is_a?(Array) }
    end
  end
end
