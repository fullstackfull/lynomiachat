module Enterprise::AutomationRule
  def actions_attributes
    super + %w[add_sla]
  end
end
