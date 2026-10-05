# Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/01-meta-api-contract.md sections 6 and 7): the one
# place that decides what may be done to a template, derived from Meta's current rules rather than from what a button
# happens to show. The manager renders this list; every lifecycle endpoint enforces the same list, so hiding a control
# is never the only thing stopping an action.
#
# Meta's rules this encodes:
#   * only an APPROVED, REJECTED or PAUSED template can be edited at all;
#   * the category of an APPROVED template cannot be changed, so it is editable only while REJECTED or PAUSED;
#   * a DISABLED template cannot be deleted;
#   * a template already at Meta cannot be submitted again, and one whose submit is still in flight cannot be
#     submitted twice (the draft's own submitted_at is the claim -- see PART 7).
#
# CSAT keeps its own lifecycle (docs/whatsapp-template-manager/03-sync-and-lifecycle.md section 5.5), so its templates
# are read-only here and the manager points at the inbox's CSAT settings instead.
class Whatsapp::Templates::Actions
  EDITABLE_STATUSES = %w[APPROVED REJECTED PAUSED].freeze
  # The two statuses in which Meta also allows the category to change.
  CATEGORY_EDITABLE_STATUSES = %w[REJECTED PAUSED].freeze
  UNDELETABLE_STATUSES = %w[DISABLED].freeze

  def initialize(template)
    @template = template
  end

  RULES = { submit: :submittable?, edit: :editable?, edit_category: :category_editable?,
            delete: :deletable? }.freeze
  ACTIONS = (RULES.keys + [:duplicate]).freeze

  def all
    ACTIONS.select { |action| allowed?(action) }
  end

  def allowed?(action)
    return false if csat? && action != :duplicate
    # Duplicating only ever creates a new local draft, so nothing Meta says can forbid it.
    return true if action == :duplicate

    rule = RULES[action]
    rule.present? && send(rule)
  end

  private

  attr_reader :template

  # A draft, including one whose last submit was refused by Meta -- that draft is still the only copy and must be
  # fixable. A submit already in flight is not submittable again.
  def submittable?
    template.local? && (template.submitted_at.blank? || template.submission_error.present?)
  end

  def editable?
    return true if template.local?

    EDITABLE_STATUSES.include?(status)
  end

  def category_editable?
    return true if template.local?

    CATEGORY_EDITABLE_STATUSES.include?(status)
  end

  # A draft exists only here, so deleting it needs no Meta call at all.
  def deletable?
    return true if template.local?

    UNDELETABLE_STATUSES.exclude?(status)
  end

  def status
    template.meta_status.to_s.upcase
  end

  def csat?
    template.name.to_s.start_with?(CsatTemplateNameService::CSAT_BASE_NAME)
  end
end
