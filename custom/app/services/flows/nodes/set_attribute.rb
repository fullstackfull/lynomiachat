# Set Contact / Conversation Attribute (docs/flow-builder/04-node-contracts.md §attributes): writes one custom attribute
# the account defined, with the value checked against its definition (Flows::AttributeValue), the same way an agent's
# edit is stored. `flow.*` variables are filled in first. A value that does not fit the attribute's type, or an attribute
# deleted after the flow was published, fails the session: the conversation goes to humans and nothing is written.
class Flows::Nodes::SetAttribute < Flows::Nodes::Base
  def enter
    definition = account.custom_attribute_definitions.find_by(attribute_model: attribute_model, attribute_key: @data['key'])
    return Flows::Step.finish(:failed, code: 'attribute_missing') if definition.nil?

    value = Flows::AttributeValue.cast(definition, Flows::Variables.render(@data['value'], @run.context).strip)
    return Flows::Step.finish(:failed, code: 'invalid_attribute_value') if value.nil?

    target.update!(custom_attributes: target.custom_attributes.merge(@data['key'] => value))
    Flows::Step.next('next')
  end
end
