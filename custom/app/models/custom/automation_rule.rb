# Lynomia Automation (docs/automation/03-audience-and-commerce-conditions.md): Chatwoot's rules accept audience and
# Commerce conditions when they are valid for the rule's account: shared audiences of this account only (never a
# personal one), this account's stores, Commerce enabled, the extensions switch on, the same limits as audiences.
module Custom::AutomationRule
  def self.prepended(base)
    base.validate :lynomia_conditions
  end

  def conditions_attributes
    super + lynomia_conditions_list.pluck('attribute_key')
  end

  private

  def lynomia_conditions_list
    Array(conditions).select { |condition| Automation::LynomiaCondition.key?(condition['attribute_key']) }
  end

  def lynomia_conditions
    list = lynomia_conditions_list
    return if list.empty?
    return errors.add(:conditions, I18n.t('automation.lynomia.extensions_disabled')) unless Automation::Extensions.enabled?

    limit = Custom::Contacts::FilterService::MAX_CONDITIONS
    return errors.add(:conditions, I18n.t('automation.lynomia.too_many_conditions', count: limit)) if list.size > limit

    list.each do |condition|
      key = condition['attribute_key']
      Automation::LynomiaCondition.new(key, account: account).errors(condition['filter_operator'], condition['values']).each do |problem|
        errors.add(:conditions, I18n.t("automation.lynomia.#{problem}", key: key))
      end
    end
  end
end
