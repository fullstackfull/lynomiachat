# frozen_string_literal: true

# Records that somebody changed what the public website says.
#
# WHY THE WEBSITE NEEDS AN AUDIT TRAIL AT ALL. These rows are the only thing the public pages render from, so
# an edit here is a change to what the company claims about its own product -- with no deploy, no review and
# no diff. The repository's existing audit infrastructure already answers "who changed what and when"
# (Custom::AuditLog, the `audited` gem's own class), so this is a writer against it rather than a second log.
#
# WHAT IS RECORDED: the status transition, because publishing is the act that makes an edit public, and the
# attributes whose values a reader sees. `sections` is recorded as a SHAPE rather than wholesale -- the full
# jsonb of a long page is kilobytes of prose in an audit row, and what a reader of the trail needs is "the
# sections changed, from these types to these" with the page itself holding the current text.
#
# It follows Billing::PlanAudit exactly, including rescuing its own failure: the page is already saved by the
# time this runs, so a failed audit must not report the save as failed.
class Marketing::PageAudit
  AUDIT_EVENT = 'marketing.site_page_changed'
  TRACKED_COLUMNS = %w[status slug title description heading lede meta].freeze

  # Call right after a successful save, while `previous_changes` still holds the diff.
  def self.record(page, actor:)
    changes = page.previous_changes.slice(*TRACKED_COLUMNS)
    changes['sections'] = section_shapes(page) if page.previous_changes.key?('sections')
    return if changes.blank?

    Custom::AuditLog.create!(
      auditable: page, user: actor, action: 'update', comment: AUDIT_EVENT,
      audited_changes: changes.merge('page' => "#{page.locale}/#{page.kind}/#{page.key}")
    )
  rescue StandardError => e
    Rails.logger.error("[Marketing] could not audit the change to site page #{page&.id}: #{e.class}")
  end

  # `[before, after]` as lists of section types, which is what makes a reordering or a removal legible without
  # storing the page's whole text twice.
  def self.section_shapes(page)
    page.previous_changes['sections'].map do |value|
      Array(value).filter_map { |section| section['type'] if section.is_a?(Hash) }
    end
  end
end
