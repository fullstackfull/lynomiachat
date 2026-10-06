# Tenants consume Lynomia documentation; they do not author it. See custom/app/policies/custom/portal_policy.rb for
# why this is a policy overlay and not a route deletion.
#
# create? is the one Articles::BulkActionsController authorizes against, so denying it also stops translate,
# update_status, update_category and delete_articles.
module Custom::ArticlePolicy
  def index? = false
  def show? = false
  def create? = false
  def update? = false
  def edit? = false
  def destroy? = false
  def reorder? = false
end
