# frozen_string_literal: true

require 'administrate/field/base'

class BillingPlanLimitsField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => BillingPlan::LIMIT_KEYS }
  end

  LABELS = { 'agents' => 'Agents', 'inboxes' => 'Inboxes', 'stores' => 'Commerce stores' }.freeze

  def limits
    (data || {}).to_h
  end

  def label(key) = LABELS.fetch(key)

  def to_s
    BillingPlan::LIMIT_KEYS.map { |key| "#{label(key)}: #{limits[key].nil? ? '∞' : limits[key]}" }.join(' · ')
  end
end
