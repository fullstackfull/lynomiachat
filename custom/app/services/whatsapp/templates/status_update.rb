# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/03-sync-and-lifecycle.md §4): applies one
# `message_template_status_update` webhook to the rows of the WABA it names. The webhook is an accelerator, never the
# source of truth -- without it a status still moves on the sync that already runs, so nothing here has to be
# complete, only correct.
#
# Three things Meta's own payload makes easy to get wrong (docs/whatsapp-template-manager/01-meta-api-contract.md §8):
#
#   * `event` is a SUPERSET of the status enum. FLAGGED, LOCKED, REINSTATED and UNARCHIVED are events about a template
#     whose status may not have changed, so only a member of the status enum is written to meta_status; anything else
#     is recorded as the last event and the next sync settles the status.
#   * `message_template_id` is an Integer here and a numeric String in API reads, so it is compared as a string.
#   * `message_template_language` is `en-US` here and `en_US` in the API, so the separator is normalised before any
#     name-and-language fallback.
#
# meta_synced_at is deliberately NOT touched: one row stamped newer than its WABA peers would make every other row of
# that WABA look as though the last sync had not seen it (Whatsapp::MessageTemplate#missing_at_meta?).
class Whatsapp::Templates::StatusUpdate
  # WhatsAppBusinessHSMStatus -- the values the API itself returns.
  STATUSES = %w[APPROVED ARCHIVED DELETED DISABLED IN_APPEAL LIMIT_EXCEEDED PAUSED PENDING PENDING_DELETION
                REJECTED].freeze

  def initialize(waba_id, value)
    @waba_id = waba_id.to_s
    @value = (value || {}).with_indifferent_access
  end

  def perform
    return if @waba_id.blank? || event.blank?

    # A template Meta has just created in WhatsApp Manager has no row yet, and the payload carries no components to
    # build one from; the next sync mirrors it.
    Whatsapp::MessageTemplate.without_auditing do
      rows.each do |row|
        was = row.meta_status
        row.update!(attributes_for(row))
        report_status_change(row, was)
      end
    end
  end

  private

  # A template that Meta rejects, pauses or disables stops being sendable, and until now that happened with no log
  # line, no audit row (this runs inside without_auditing) and no notification: the first anyone knew was a campaign
  # or an automation quietly refusing to send. Only a real transition is reported, so the repeated events Meta sends
  # about an unchanged template do not become noise.
  #
  # APPROVED is the one an operator was waiting for, so it is findable at info. PAUSED, REJECTED and LIMIT_EXCEEDED
  # are recoverable and expected enough not to page. DISABLED is terminal -- the template can never be sent again and
  # has to be replaced -- so it is the one error.
  TERMINAL_STATUSES = %w[DISABLED DELETED].freeze
  ACTIONABLE_STATUSES = %w[REJECTED PAUSED LIMIT_EXCEEDED IN_APPEAL PENDING_DELETION].freeze

  def report_status_change(row, previous_status)
    return if row.meta_status == previous_status

    Lynomia::OperatorLog.emit(
      status_level(row.meta_status), 'WHATSAPP_TEMPLATE_STATUS_CHANGED',
      account: row.account_id, waba: row.business_account_id, template: row.name, language: row.language,
      category: row.category, from: previous_status.presence || 'none', to: row.meta_status,
      reason: row.meta_payload['rejected_reason'], detail: row.meta_payload['rejection_info']
    )
  end

  def status_level(status)
    return :error if TERMINAL_STATUSES.include?(status)
    return :warn if ACTIONABLE_STATUSES.include?(status)

    :info
  end

  def rows
    scope = Whatsapp::MessageTemplate.where(business_account_id: @waba_id)
    by_id = meta_id.present? ? scope.where(meta_template_id: meta_id) : scope.none
    return by_id if by_id.exists?

    return scope.none if name.blank? || language.blank?

    scope.where(name: name).where('lower(language) = ?', language.downcase)
  end

  def attributes_for(row)
    attributes = { meta_payload: row.meta_payload.to_h.merge(payload_extras) }
    attributes[:meta_status] = event if STATUSES.include?(event)
    attributes[:meta_template_id] = meta_id if row.meta_template_id.blank? && meta_id.present?
    attributes[:category] = category if category.present?
    attributes
  end

  # `reason` carries the same enum as the API's `rejected_reason`, so it lands on the same key the detail view reads.
  # `rejection_info` is webhook-only, and the only place Meta explains a rejection in words.
  def payload_extras
    {
      'last_event' => event,
      'rejected_reason' => @value[:reason],
      'rejection_info' => @value[:rejection_info],
      'disable_info' => @value[:disable_info],
      'other_info' => @value[:other_info]
    }.compact
  end

  def event
    @event ||= @value[:event].to_s.upcase
  end

  def meta_id
    @meta_id ||= @value[:message_template_id].presence&.to_s
  end

  def name
    @name ||= @value[:message_template_name].to_s
  end

  def language
    @language ||= @value[:message_template_language].to_s.tr('-', '_')
  end

  def category
    @category ||= @value[:message_template_category].presence
  end
end
