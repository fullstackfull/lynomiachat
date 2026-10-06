# Tenants consume Lynomia documentation; they do not author it. See custom/app/policies/custom/portal_policy.rb for
# why this is a policy overlay and not a route deletion.
module Custom::CategoryPolicy
  def index? = false
  def show? = false
  def create? = false
  def update? = false
  def edit? = false
  def destroy? = false
  def reorder? = false
end
