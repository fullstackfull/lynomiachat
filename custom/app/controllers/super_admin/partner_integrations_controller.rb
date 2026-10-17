# PARTNER INTEGRATIONS, for a Lynomia operator (P6C).
#
# Lynomia's Super Admin already administers PlatformApp through Administrate: its name, its
# token, create and destroy. What it could not answer is everything an operator actually asks
# when a partner's merchant complains -- what is this integration permitted, which workspaces
# does it hold, is any of them failing, and what has it done lately. This is that screen, and
# it EXTENDS the existing administration rather than replacing it: creating, destroying and
# rotating an app stay where they are, and nothing here widens what an app may do.
#
# READ ONLY. There is no operator mutation on this surface at all, which is why none of its
# routes is anything but a GET. The acts that change an integration already have owners -- the
# Administrate screen for the app itself, the Operations Center for a signal, and the partner's
# own console for its installations -- and a second place to do them is a second place for
# them to disagree.
#
# Hand-written ERB inside the Administrate shell, like the Operations Center, because what is
# administered is a console across several models rather than one record. That choice carries
# an obligation paid in the same commit: `partner_integrations` is in the exclusion list in
# app/views/super_admin/application/_navigation.html.erb, because Administrate enumerates every
# controller under super_admin/ and a hand-written one with no dashboard raises inside the
# navigation partial -- breaking EVERY Super Admin page, not just this one.
class SuperAdmin::PartnerIntegrationsController < SuperAdmin::ApplicationController
  def show
    @apps = Operations::PartnerOverview.apps
  end

  def app
    platform_app = PlatformApp.find_by(id: params[:id])
    # find_by and redirect, never find!, which is how every lookup on this surface behaves: an
    # operator following a stale link gets the list back with a note, not a 500.
    return redirect_to(super_admin_partner_integrations_path, alert: t('super_admin.partner_integrations.not_found')) if platform_app.nil?

    @overview = Operations::PartnerOverview.new(platform_app).call
  end
end
