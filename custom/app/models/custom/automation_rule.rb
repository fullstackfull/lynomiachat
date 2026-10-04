# Lynomia Automation (docs/automation/03-audience-and-commerce-conditions.md): Chatwoot's rules accept audience and
# Commerce conditions when they are valid for the rule's account: shared audiences of this account only (never a
# personal one), this account's stores, Commerce enabled, the extensions switch on, the same limits as audiences.
#
# Commerce triggers (docs/automation/04-commerce-triggers.md): `commerce_order_*` rules need Lynomia Commerce, run at
# once (no delay), and offer no customer-facing message action: a store event is not a customer message, and a WhatsApp
# conversation may be outside its 24-hour window. The event's store and platform conditions exist only on these rules.
module Custom::AutomationRule
  CUSTOMER_MESSAGE_ACTIONS = %w[send_message send_attachment].freeze

  def self.prepended(base)
    base.validate :lynomia_conditions
    base.validate :commerce_trigger
  end

  # The seven provider-neutral order events. Listed here whether or not the account is entitled to them: the name
  # is a real trigger either way, and entitlement is already reported separately by `commerce_trigger_rules`, which
  # gives the accurate reason rather than "not a supported trigger".
  def event_names
    super + Automation::CommerceEvents::EVENTS
  end

  def conditions_attributes
    super + lynomia_conditions_list.pluck('attribute_key')
  end

  private

  def commerce_trigger?
    Automation::CommerceEvents.event?(event_name)
  end

  def commerce_trigger
    return commerce_trigger_rules if commerce_trigger?
    return unless lynomia_conditions_list.any? { |condition| Automation::LynomiaCondition.event_key?(condition['attribute_key']) }

    errors.add(:conditions, I18n.t('automation.lynomia.event_condition_without_trigger'))
  end

  def commerce_trigger_rules
    return errors.add(:event_name, I18n.t('automation.lynomia.extensions_disabled')) unless Automation::Extensions.enabled?
    return errors.add(:event_name, I18n.t('automation.lynomia.commerce_disabled')) unless account&.feature_enabled?('lynomia_commerce')

    errors.add(:execution_delay, I18n.t('automation.lynomia.no_delay')) if execution_delay.present?
    messages = Array(actions).pluck('action_name') & CUSTOMER_MESSAGE_ACTIONS
    errors.add(:actions, I18n.t('automation.lynomia.no_customer_message', actions: messages.join(', '))) if messages.any?
  end

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
