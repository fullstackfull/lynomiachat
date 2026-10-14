# Quote requests from the public pricing page.
#
# Administrate's default behaviour is right for everything except the order and the writes: newest first,
# because an operator wants the most recent lead, and no `new`/`create` because a visitor writes these rows.
# `authenticate_super_admin!` comes from SuperAdmin::ApplicationController and is the only authorization this
# surface has or needs.
class SuperAdmin::SiteQuoteRequestsController < SuperAdmin::ApplicationController
  def scoped_resource
    super.newest_first
  end
end
