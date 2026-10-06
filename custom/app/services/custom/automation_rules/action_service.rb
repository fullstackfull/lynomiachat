# Lynomia Automation actions (docs/pre-p7-closeout/03-template-automation-action.md).
#
# One action, kept as thin as every other action in AutomationRules::ActionService: it resolves nothing and decides
# nothing, it hands the rule's configuration to Custom::AutomationRules::TemplateAction. Dispatch is the parent's
# own `send(action[:action_name], action[:action_params])`, so no registry or dispatcher is added.
#
# `action_params` follows the existing convention — an array whose first element is the action's configuration, the
# same shape `send_email_to_team` already uses. It carries an inbox id, a template name, a language and a variable
# mapping, and never a credential: the channel's token is read from the inbox at send time by the existing sender.
module Custom::AutomationRules::ActionService
  private

  # Every action in the parent is private and reached through its own `send`, so this one matches.
  def send_whatsapp_template(params)
    Custom::AutomationRules::TemplateAction.new(
      rule: @rule, account: @account, conversation: @conversation, config: Array(params).first
    ).perform
  end
end
