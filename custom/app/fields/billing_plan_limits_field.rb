# frozen_string_literal: true

require 'administrate/field/base'

class BillingPlanLimitsField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => BillingPlan::LIMIT_KEYS }
  end

  # ONE ENTRY PER BillingPlan::LIMIT_KEYS, and `label` fetches rather than defaults because a
  # missing entry is a deployment mistake to see immediately, not a blank box on an operator's
  # form. It is the same reason the counting side keeps Billing::ResourceLimit::METERED: a key
  # added to LIMIT_KEYS has to be given a meaning in both places, and a silent fallback here
  # would hide the second half of that.
  LABELS = { 'agents' => 'Agents', 'inboxes' => 'Inboxes', 'stores' => 'Commerce stores', 'flows' => 'Flows',
             'campaign_sends' => 'Campaign sends per period' }.freeze

  def limits
    (data || {}).to_h
  end

  def label(key) = LABELS.fetch(key)

  def to_s
    BillingPlan::LIMIT_KEYS.map { |key| "#{label(key)}: #{limits[key].nil? ? '∞' : limits[key]}" }.join(' · ')
  end
end
