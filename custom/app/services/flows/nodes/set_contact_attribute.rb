class Flows::Nodes::SetContactAttribute < Flows::Nodes::SetAttribute
  private

  def attribute_model = 'contact_attribute'

  def target = @run.contact
end
