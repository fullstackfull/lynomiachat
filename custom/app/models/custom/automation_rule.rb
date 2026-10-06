# Lynomia Automation (docs/automation/03-audience-and-commerce-conditions.md): Chatwoot's rules accept audience and
# Commerce conditions when they are valid for the rule's account: shared audiences of this account only (never a
# personal one), this account's stores, Commerce enabled, the extensions switch on, the same limits as audiences.
#
# Commerce triggers (docs/automation/04-commerce-triggers.md): `commerce_order_*` and `commerce_cart_abandoned` rules
# need Lynomia Commerce, run at once (no delay), and offer no FREE-FORM customer message action: a store event is not a
# customer message, and a WhatsApp conversation may be outside its 24-hour window. The event's store and platform
# conditions exist only on these rules.
#
# The one customer-facing action they may use is `send_whatsapp_template`
# (docs/pre-p7-closeout/03-template-automation-action.md), because an approved template is the only thing WhatsApp
# permits outside that window. It is deliberately NOT added to CUSTOMER_MESSAGE_ACTIONS: that list is the free-form
# deny-list and stays exactly as it was, so adding the template action widens nothing else.
module Custom::AutomationRule
  CUSTOMER_MESSAGE_ACTIONS = %w[send_message send_attachment].freeze
  TEMPLATE_ACTION = 'send_whatsapp_template'.freeze
  TEMPLATE_ACTION_KEYS = %w[inbox_id name language].freeze

  def self.prepended(base)
    base.validate :lynomia_conditions
    base.validate :commerce_trigger
    base.validate :template_action_configured
  end

  # The action has to be declared here or `json_actions_format` refuses the rule: `actions_attributes` is a plain
  # allow-list and Chatwoot's own validation subtracts it from the rule's action names.
  def actions_attributes
    super + [TEMPLATE_ACTION]
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

  # A rule naming a template it cannot identify is an invisible no-op, which is the failure mode P0/D8 exists to
  # prevent: the rule saves, looks created, and sends nothing. The inbox, name and language are what the send-time
  # gate needs to find the template at all, so their absence is a configuration error, not a runtime surprise.
  #
  # Checked only while the rule is ACTIVE, because a disabled rule is a draft. That is what lets a starter recipe
  # create the trigger and the action and leave the inbox and template for the person to choose in the rule editor,
  # where the real control lives — rather than growing a second template selector in the recipe wizard. The rule
  # then cannot be switched on until it is complete, so an incomplete draft can never run.
  def template_action_configured
    return unless active?

    Array(actions).each do |action|
      next unless action['action_name'] == TEMPLATE_ACTION

      config = Array(action['action_params']).first
      missing = TEMPLATE_ACTION_KEYS.reject { |key| config.is_a?(Hash) && config.with_indifferent_access[key].present? }
      errors.add(:actions, I18n.t('automation.lynomia.template_action_incomplete', keys: missing.join(', '))) if missing.any?
    end
  end

  def commerce_trigger?
    Automation::CommerceEvents.event?(event_name)
  end

  def commerce_trigger
    return commerce_trigger_rules if commerce_trigger?
    return unless lynomia_conditions_list.any? { |condition| Automation::LynomiaCondition.event_key?(condition['attribute_key']) }

    errors.add(:conditions, I18n.t('automation.lynomia.event_condition_without_trigger'))
  end

  def commerce_trigger_rules
    return errors.add(:event_name, extensions_disabled_error) unless Automation::Extensions.enabled?
    return errors.add(:event_name, I18n.t('automation.lynomia.commerce_disabled')) unless account&.feature_enabled?('lynomia_commerce')

    errors.add(:execution_delay, I18n.t('automation.lynomia.no_delay')) if execution_delay.present?
    messages = Array(actions).pluck('action_name') & CUSTOMER_MESSAGE_ACTIONS
    errors.add(:actions, I18n.t('automation.lynomia.no_customer_message', actions: messages.join(', '))) if messages.any?
  end

  # The message names the product, so it reads the installation's own name rather than carrying a brand literal.
  def extensions_disabled_error
    I18n.t('automation.lynomia.extensions_disabled',
           installation_name: GlobalConfigService.load('INSTALLATION_NAME', 'Chatwoot'))
  end

  def lynomia_conditions_list
    Array(conditions).select { |condition| Automation::LynomiaCondition.key?(condition['attribute_key']) }
  end

  def lynomia_conditions
    list = lynomia_conditions_list
    return if list.empty?
    return errors.add(:conditions, extensions_disabled_error) unless Automation::Extensions.enabled?

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
