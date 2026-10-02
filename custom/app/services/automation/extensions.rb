# Lynomia Automation's kill switch (docs/automation/05-runtime-security-and-tenancy.md). Off, only what Lynomia added to
# Chatwoot automation stops: rules with an audience or Commerce condition no longer match, Commerce triggers are not
# dispatched, and such conditions cannot be saved. Every other rule keeps running exactly as before.
#
#   LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED (installation config, else ENV; default true)
module Automation::Extensions
  def self.enabled?
    value = GlobalConfig.get_value('LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED')
    ActiveModel::Type::Boolean.new.cast(value.nil? ? ENV.fetch('LYNOMIA_AUTOMATION_EXTENSIONS_ENABLED', 'true') : value) != false
  end
end
