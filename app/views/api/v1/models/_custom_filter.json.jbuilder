json.id resource.id
json.name resource.name
json.filter_type resource.filter_type
json.query resource.query
json.created_at resource.created_at
json.updated_at resource.updated_at
json.shared resource.shared
if resource.shared?
  # Lynomia shared audiences: the automation rules and the campaigns still to send that reference it
  # (docs/automation/02-shared-audiences.md, docs/campaigns/03-audience-dependency.md).
  rules = Audience::Usage.rules(resource)
  json.automation_rules_count rules.size
  json.active_automation_rules_count rules.count(&:active?)
  json.campaigns_count Audience::Usage.campaigns(resource).count
end
