# Is this request on the platform's OWN host?
#
# This is the boundary the homepage cutover rests on. `/` has to answer three different things depending only
# on the host it was asked for:
#
#   - the platform's own host (`FRONTEND_URL`) -> the Arabic marketing homepage
#   - a tenant's registered Help Center custom domain -> that portal's home, unchanged
#   - anything else -> DashboardController, unchanged
#
# THE SAME EXPRESSION ALREADY EXISTS, in the opposite sense, in
# DashboardController#render_hc_if_custom_domain (app/controllers/dashboard_controller.rb:64-66): it returns
# early -- declining to render a Help Center -- when the host IS this one. The two have to agree exactly, or
# `/` is either claimed by both or by neither, so the expression is named here once and the route constraint
# calls it rather than restating it. The dashboard controller is deliberately left alone: it is the custom
# domain path the cutover must not disturb.
#
# NOT `DomainHelper.chatwoot_domain?`, which also matches `HELPCENTER_URL`. On an installation that sets
# HELPCENTER_URL to a separate hostname, that host serves the documentation portal, and putting Lynomia's
# marketing homepage on it would take the Help Center's own root away.
#
# WITH `FRONTEND_URL` UNSET this returns false for every request, which is the safe direction: `/` keeps the
# behaviour it has today (DashboardController) rather than the marketing site appearing on a host nobody has
# claimed. That is also why the test suite's existing `/` examples are unaffected -- the variable is unset
# there, and the specs that exercise the marketing root set it explicitly.
#
# `URI.parse` is left to raise on a malformed FRONTEND_URL rather than rescued: a value that cannot be parsed
# is a deployment mistake, and the dashboard controller already fails the same way on the same value.
class Marketing::OfficialHost
  def self.host = URI.parse(ENV.fetch('FRONTEND_URL', '')).host

  def self.matches?(request)
    official = host
    official.present? && request.host == official
  end
end
