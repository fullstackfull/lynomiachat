# frozen_string_literal: true

# WHAT A PLAN ACTUALLY INCLUDES, GROUPED SO A BUYER CAN READ IT.
#
# A plan's `features` column is a list of flag names -- `agent_bots`, `custom_attributes`,
# `whatsapp_embedded_signup_inbox_creation`. That is the truth, and it is unreadable. This turns it into
# named capabilities under headings, in the reader's language, WITHOUT deciding anything: the list comes
# from the row, so ticking a box in Super Admin changes the public page on the next request and nothing
# here has to be edited.
#
# THE THREE RULES THIS ENFORCES, because each of them is a way a pricing page lies:
#
#   1. NOTHING IS SHOWN THAT THE PLAN DOES NOT HAVE. Every capability printed comes from `plan.features`.
#      There is no "all plans include..." list, because there is no column that says so.
#
#   2. NOTHING IS SHOWN THAT WE MAY NOT SELL. The flags are intersected with
#      `BillingPlan.assignable_features`, which already excludes chatwoot-internal, deprecated and
#      Enterprise-licensed (`premium`) capabilities. A row that somehow carries one -- a hand-edited record,
#      a flag that was assignable and later was not -- is dropped rather than advertised.
#
#   3. NOTHING DISAPPEARS SILENTLY. A flag that exists upstream but is not in CATEGORIES lands under
#      `:other` instead of vanishing. The failure mode of the alternative is the worst kind: somebody adds a
#      capability, every plan gets it, and the page that sells it never mentions it.
#
# ON THE ARABIC FALLBACK. English names come from `display_name` in config/features.yml -- one source, and
# a new flag is named the day it is added. Arabic names are translations keyed by flag name, and a flag with
# no Arabic entry yet falls back to its English name rather than being hidden. That is a deliberate choice
# between two bad outcomes: an untranslated capability is visible and fixable, a hidden one is neither, and
# this page is a commercial document where an omission costs more than an inconsistency.
class Marketing::PlanFeatures
  # Only categories the real flags support. There is no "Advanced" bucket invented to look fuller: every
  # heading below exists because flags fall under it.
  CATEGORIES = {
    conversations: %w[inbox_management labels canned_responses macros voice_recorder
                      auto_resolve_conversations custom_attributes],
    channels: %w[channel_email channel_website channel_facebook channel_instagram channel_tiktok
                 inbound_emails email_continuity_on_api_channel whatsapp_embedded_signup_inbox_creation
                 whatsapp_manual_transfer],
    automation: %w[automations delayed_automations agent_bots captain_tasks lynomia_flow_builder],
    contacts: %w[crm lynomia_unified_identity data_import ip_lookup],
    campaigns: %w[campaigns whatsapp_campaign],
    analytics: %w[reports],
    team: %w[agent_management team_management],
    security: %w[custom_roles],
    integrations: %w[integrations api_and_webhooks linear_integration crm_integration notion_integration],
    commerce: %w[lynomia_commerce],
    support: %w[help_center lynomia_support_tickets],
    branding: %w[custom_reply_email custom_reply_domain branded_email_templates]
  }.freeze

  # Where a flag goes when CATEGORIES has not heard of it. See rule 3.
  FALLBACK_CATEGORY = :other

  # The order headings appear in, most-asked-about first. :other is last because by construction it holds
  # whatever nobody has categorised yet.
  ORDER = (CATEGORIES.keys + [FALLBACK_CATEGORY]).freeze

  Capability = Struct.new(:name, :label, :category, keyword_init: true)

  class << self
    # Every capability this plan includes, in ORDER, as [category, [Capability, ...]] pairs. Empty
    # categories are not returned, so a plan with three features renders three rows and not twelve headings.
    def grouped(plan, locale:)
      in_category_order(for_plan(plan, locale: locale))
    end

    # Flat, in ORDER, for the card's summary line.
    def for_plan(plan, locale:)
      sorted(sellable(plan).map { |name| capability(name, locale: locale) })
    end

    # Every capability any listed plan sells, grouped -- the row set of the comparison table. Built from the
    # union of the plans on the page rather than from the whole catalogue, so the table compares what is
    # actually on offer instead of listing forty rows that are blank in every column.
    def comparison_rows(plans, locale:)
      names = plans.flat_map { |plan| sellable(plan) }.uniq
      in_category_order(sorted(names.map { |name| capability(name, locale: locale) }))
    end

    def category_label(category, locale:)
      I18n.t("marketing.pricing.feature_categories.#{category}", locale: locale,
                                                                 default: category.to_s.humanize)
    end

    private

    # ORDER is the one authority on where a heading sits, and an uncategorised capability sorts last rather
    # than raising -- which is rule 3 again, in the sort.
    def position(category) = ORDER.index(category) || ORDER.length

    def sorted(capabilities)
      capabilities.sort_by { |capability| [position(capability.category), capability.label] }
    end

    # group_by keeps insertion order, so an already-sorted list groups in the same order.
    def in_category_order(capabilities)
      capabilities.group_by(&:category).sort_by { |category, _| position(category) }
    end

    # Rules 1 and 2 in one place: the plan's own flags, narrowed to what may be sold.
    def sellable(plan)
      Array(plan.features) & assignable_names
    end

    def assignable_names
      BillingPlan.assignable_features.pluck('name')
    end

    def capability(name, locale:)
      Capability.new(name: name, label: label_for(name, locale: locale), category: category_for(name))
    end

    def category_for(name)
      CATEGORIES.each { |category, names| return category if names.include?(name) }
      FALLBACK_CATEGORY
    end

    # Arabic if we have it, else the catalogue's English name. Never the raw flag.
    def label_for(name, locale:)
      I18n.t("marketing.pricing.features.#{name}", locale: locale, default: english_names[name] || name.humanize)
    end

    def english_names
      BillingPlan.assignable_features.to_h { |f| [f['name'], f['display_name']] }
    end
  end
end
