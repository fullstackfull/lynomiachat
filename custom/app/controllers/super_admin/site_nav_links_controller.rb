# The header and footer rows of the official website.
#
# Administrate's defaults are right for everything except the order: locale, then placement, then the position
# an operator set, which is the order the public navigation renders in and therefore the order an operator
# needs to see while reordering it. `authenticate_super_admin!` comes from SuperAdmin::ApplicationController
# and is the only authorization this surface has or needs.
class SuperAdmin::SiteNavLinksController < SuperAdmin::ApplicationController
  def scoped_resource
    super.order(:locale, :placement, :position, :id)
  end
end
