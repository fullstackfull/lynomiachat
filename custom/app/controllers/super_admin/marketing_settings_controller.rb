# The website's sales settings: where a quote request from the pricing page is emailed.
#
# ONE SETTING, EDITABLE, WITH NO CODE AND NO DEPLOY. The owner's requirement is that the recipient address be
# entered, replaced and cleared from Super Admin and take effect without restarting Rails
# (docs/official-website/06-super-admin-cms-design.md). `MARKETING_QUOTE_NOTIFICATION_EMAIL` was already the
# single source of truth and stays so: this screen is a typed, validated, audited editor for that one
# Installation Config row, not a second store beside it. Marketing::QuoteSettings holds the rules.
#
# WHY NOT JUST INSTALLATION CONFIGS. That page exists and still works, but it is a flat list of every key in
# the installation with a free-text value field: no email validation, no audit entry naming the change, no
# statement of what happens while the key is empty, and no way to tell whether the address actually receives
# anything. The owner's brief rules out requiring an operator to find an undocumented configuration key, so
# the field lives beside the leads it governs instead -- reached from the Quote Requests screen.
#
# SERVER-RENDERED ERB, NO VUE ISLAND, following SuperAdmin::OperationsController and
# SuperAdmin::PlatformSupportController: a form, two buttons and a status block need no client state. It also
# avoids the one-widget-per-page limit `render_vue_component` imposes by hardcoding `id: 'app'`.
#
# AUTHORIZATION is `authenticate_super_admin!`, applied by SuperAdmin::ApplicationController to every action.
# That is the whole boundary on this surface and this controller does not invent a second one. CSRF comes from
# ApplicationController's `protect_from_forgery`, so both writes are POST/PATCH forms with the Rails token.
class SuperAdmin::MarketingSettingsController < SuperAdmin::ApplicationController
  def show
    load_state
  end

  # Save or replace the address. An empty field is a legitimate value meaning "send nothing" -- the same thing
  # the Clear button does, so a cleared field submitted through Save behaves identically.
  def update
    apply(Marketing::QuoteSettings.update(params[:quote_notification_email], actor: current_super_admin))
  end

  # Clear is its own action rather than "save an empty box", because turning notifications off is a decision
  # and the button that does it should say so. It writes through the same validated path.
  def clear
    apply(Marketing::QuoteSettings.update('', actor: current_super_admin))
  end

  # Deliberately a POST: sending mail is not something a pasted link should be able to do.
  def test_email
    apply(Marketing::QuoteSettings.send_test(actor: current_super_admin))
  end

  private

  # Every write ends the same way: a flash naming what happened, and a redirect so a refresh does not repeat
  # it. `notice` for an outcome the operator asked for, `alert` for a refusal -- which is also how the two are
  # styled by the shared Administrate layout.
  def apply(result)
    # `_flashes.html.erb` renders a flash with `html_safe`, so the detail is escaped here. Nothing unvalidated
    # reaches it today -- a refusal carries no detail and an accepted address has passed the email regex -- but
    # the escape is what keeps that true of the next message somebody adds.
    message = t("super_admin.marketing_settings.flash.#{result.message}",
                detail: ERB::Util.html_escape(result.detail))
    flash[result.ok? ? :notice : :error] = message
    redirect_to super_admin_marketing_settings_path
  end

  def load_state
    @address = Marketing::QuoteSettings.address
    @status = Marketing::QuoteSettings.status
    @last_delivery = Marketing::QuoteSettings.last_delivery
    @last_failure = Marketing::QuoteSettings.last_failure
    @unanswered_count = SiteQuoteRequest.status_new_request.count
  end
end
