# Lynomia Flow Builder's availability (docs/flow-builder/08-security-and-tenancy.md).
#
#   lynomia_flow_builder                  account feature: the builder and flow bots of the account
#   LYNOMIA_FLOW_BUILDER_ENABLED          installation config, else ENV, default on: the emergency switch. Off, no flow
#                                         session starts or advances (live ones are handed to humans when they would
#                                         next advance); conversations, WhatsApp, Automation and webhook bots carry on.
module Flows::Switch
  def self.enabled?
    value = GlobalConfig.get_value('LYNOMIA_FLOW_BUILDER_ENABLED')
    ActiveModel::Type::Boolean.new.cast(value.nil? ? ENV.fetch('LYNOMIA_FLOW_BUILDER_ENABLED', 'true') : value) != false
  end

  def self.available?(account) = enabled? && account.feature_enabled?('lynomia_flow_builder')
end
