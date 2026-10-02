# The automation rules that reference a shared audience through a `contact_audience` condition
# (docs/automation/02-shared-audiences.md). A rule stores only the audience id, never its conditions, so this is what
# keeps a referenced audience from being deleted or made personal.
module Audience::Usage
  CONDITION_KEY = 'contact_audience'.freeze

  def self.rules(custom_filter)
    candidates = custom_filter.account.automation_rules.where('conditions @> ?', [{ attribute_key: CONDITION_KEY }].to_json)
    candidates.select do |rule|
      rule.conditions.any? do |condition|
        condition['attribute_key'] == CONDITION_KEY && Array(condition['values']).map(&:to_s).include?(custom_filter.id.to_s)
      end
    end
  end
end
