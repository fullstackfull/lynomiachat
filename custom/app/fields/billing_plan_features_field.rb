# frozen_string_literal: true

require 'administrate/field/base'

class BillingPlanFeaturesField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => [] }
  end

  def selected
    Array(data)
  end

  def options
    BillingPlan.assignable_features
  end

  def selected_names
    options.select { |f| selected.include?(f['name']) }.pluck('display_name')
  end
end
