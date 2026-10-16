# Retired marketing URLs.
#
# Newest first: a redirect is almost always added because a slug was just renamed, so the one an operator
# wants to check is the one they just made.
class SuperAdmin::SiteRedirectsController < SuperAdmin::ApplicationController
  def scoped_resource
    super.order(created_at: :desc, id: :desc)
  end
end
