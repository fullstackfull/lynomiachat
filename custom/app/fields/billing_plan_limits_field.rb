# frozen_string_literal: true

require 'administrate/field/base'

class BillingPlanLimitsField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => BillingPlan::LIMIT_KEYS }
  end

  def limits
    (data || {}).to_h
  end

  def to_s
    BillingPlan::LIMIT_KEYS.map { |key| "#{key.humanize}: #{limits[key].nil? ? '∞' : limits[key]}" }.join(' · ')
  end
end
