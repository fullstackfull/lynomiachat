# B15 -- a channel's configuration changes (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# Upstream declares the hook and leaves it empty (app/models/concerns/channelable.rb:7,10). This fills it, and
# the three decisions in it are the whole of the package point:
#
# 1. **No credential, ever, by construction.** A channel's `provider_config` holds the access tokens, app
#    secrets and verify tokens the integration runs on (Channel::Whatsapp::SECRET_PROVIDER_CONFIG_KEYS). Only
#    the NAMES of the keys that changed are recorded, never a value -- not a masked one, not a prefix, not a
#    hash. So a credential rotation is recorded as the event it is, which is what package B §5 asks for, and the
#    value is absent from the store rather than withheld on the way out.
#
# 2. **Bookkeeping is not an event.** A channel row is written by the product about itself far more often than
#    by an operator: the template snapshot is replaced on every sync, the number's health is re-checked on a
#    schedule, and a reauthorization latch flips on a failed call. None of that is a change anybody asked for,
#    and a trail full of it is a trail nobody reads.
#
# 3. **The entry is an inbox update.** The trail's vocabulary is the browser's
#    (app/javascript/dashboard/helper/auditlogHelper.js), and it has a label for an inbox being edited and none
#    for any channel class. Recording the change against the inbox is both the labelled event and the true one:
#    what the operator edited was the inbox's channel configuration.
module Custom::Channelable
  AUDIT_EVENT = 'channel.configuration_changed'.freeze
  CREDENTIALS_EVENT = 'channel.credentials_changed'.freeze

  # Written by the product about itself. Named per concern rather than per channel class, because every one of
  # these columns means the same thing wherever it appears. Reauthorization state is deliberately absent: it is
  # not a column at all, it lives in Redis (app/models/concerns/reauthorizable.rb).
  BOOKKEEPING_COLUMNS = %w[
    updated_at created_at
    message_templates message_templates_last_updated
    content_templates content_templates_last_updated
    phone_number_health phone_number_health_checked_at phone_number_health_error
  ].freeze

  # Keys the product maintains inside provider_config without being asked. `webhook_verify_token` is a
  # credential and is excluded by the credential rule as well; it is named here so that a channel whose only
  # change was its own generated token produces no entry at all.
  BOOKKEEPING_CONFIG_KEYS = %w[webhook_verify_token message_templates].freeze

  def create_audit_log_entry
    return if audited_inbox.blank?

    changed = operator_visible_changes
    rotated = rotated_credential_names
    return if changed.empty? && rotated.empty?

    AuditTrail::Event.record(
      action: 'update', auditable: audited_inbox, account: account,
      comment: rotated.any? ? CREDENTIALS_EVENT : AUDIT_EVENT,
      changes: changed.merge('rotated_fields' => rotated).compact_blank
    )
  end

  private

  # `has_one :inbox` is declared with `touch: true`, so saving a brand-new channel evaluates the association in
  # order to touch it -- and caches nil, because the inbox is created afterwards. A later update of that same
  # instance would then see no inbox and record nothing. One reload when the cache reads empty is enough, and
  # costs a query only in the case that would otherwise be silently wrong.
  def audited_inbox
    inbox || reload_inbox
  end

  # `saved_changes` rather than the record's current attributes: the trail's value is the before and the after,
  # and this runs in an `after_update` where both are still available.
  def operator_visible_changes
    saved_changes.except(*BOOKKEEPING_COLUMNS)
                 .reject { |column, _pair| AuditTrail::Secrets.secret_key?(column) }
                 .to_h { |column, pair| [column, column == 'provider_config' ? config_change_summary(pair) : pair] }
                 .compact_blank
  end

  # A provider configuration is a document, and most of what moves in it is either a credential or the
  # product's own bookkeeping. What a reader needs is which settings changed and to what -- so the credential
  # keys are dropped here and reported separately by name, and everything else keeps its before and after.
  def config_change_summary(pair)
    before, after = Array(pair).map { |value| value.is_a?(Hash) ? value : {} }
    settings = (before.keys | after.keys) - BOOKKEEPING_CONFIG_KEYS
    settings.reject { |key| AuditTrail::Secrets.secret_key?(key) }
            .reject { |key| before[key] == after[key] }
            .index_with { |key| [before[key], after[key]] }
            .presence
  end

  # The names alone. A rotation is worth recording; the old and the new value never are.
  def rotated_credential_names
    return [] unless saved_change_to_attribute?(:provider_config)

    before, after = saved_change_to_attribute(:provider_config).map { |value| value.is_a?(Hash) ? value : {} }
    ((before.keys | after.keys) - BOOKKEEPING_CONFIG_KEYS)
      .select { |key| AuditTrail::Secrets.secret_key?(key) }
      .reject { |key| before[key] == after[key] }
      .sort
  end
end
