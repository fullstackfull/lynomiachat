# Every Platform Support email, customer side and operator side, in one mailer.
#
# ONE CLASS, TWO AUDIENCES, AND NO SHARED RECIPIENT LOGIC BETWEEN THEM. The customer messages address the
# reporter (and the account's administrators when the reporter is not one); the operator messages address the
# assignee and the installation's support alias. The two sets of recipients are built by different private
# methods that share nothing, so a change to one cannot widen the other.
#
# NEVER `AgentNotifications::ConversationNotificationsMailer`. That mailer is reached by
# `Notification::EmailNotificationService`, which calls `public_send(notification_type, ...)` on it
# (app/services/notification/email_notification_service.rb:21-23) -- there is no `platform_support_reply`
# method there and there must never be one. Platform Support email is this file (§5).
#
# `mailer_name` is set so the templates live at `app/views/platform_support_mailer/`, which is the path the
# implementation contract names. Templates are ERB, not Liquid: `<%= %>` escapes by default, a ticket subject
# and a message body are customer-supplied plain text, and this module has no HTML column anywhere
# (03-authorization-security.md §9).
#
# NO SMTP PRE-CHECK. `ApplicationMailer` already installs `rescue_from(*ExceptionList::SMTP_EXCEPTIONS)`, so a
# delivery failure is logged and does not fail the request that saved the reply -- which is the rule
# 06-sla-notifications.md states. A second guard that silently returns would hide a misconfigured relay
# instead.
#
# RETURNING WITHOUT CALLING `mail` yields an `ActionMailer::Base::NullMail`, so `deliver_later` on a refused
# message is a no-op. That is the mechanism behind "an installation with no alias configured sends no operator
# email": nothing is queued and nothing is invented.
#
# NO BODY, NO CREDENTIAL AND NO INTERNAL NOTE reaches an operator email's subject line, and no internal note
# reaches a customer email at all -- a note has no mailer action here, by construction rather than by a filter.
class PlatformSupport::TicketMailer < ApplicationMailer
  self.mailer_name = 'platform_support_mailer'

  # Private, then exposed: a PUBLIC instance method on a mailer is a mailer action, so these would otherwise
  # become deliverable messages.
  helper_method :ticket_url, :staff_ticket_url

  # --- customer side -------------------------------------------------------------------------------------

  def ticket_created(ticket)
    @ticket = ticket
    customer_mail(ticket, [reporter_email(ticket)], subject_for(ticket, 'ticket_created'))
  end

  # The one email that matters. The operator's own name is never in it: the author a customer reads is the
  # desk, which is the same rule the tenant serializer applies to `author_name` (§2).
  def operator_replied(ticket, message)
    @ticket = ticket
    @message = message
    customer_mail(ticket, customer_recipients(ticket), subject_for(ticket, 'operator_replied'))
  end

  def ticket_resolved(ticket)
    @ticket = ticket
    customer_mail(ticket, [reporter_email(ticket)], subject_for(ticket, 'ticket_resolved'))
  end

  # The only status change that ASKS something of the customer, which is why it is the only one that mails.
  def waiting_on_customer(ticket)
    @ticket = ticket
    customer_mail(ticket, [reporter_email(ticket)], subject_for(ticket, 'waiting_on_customer'))
  end

  # --- operator side -------------------------------------------------------------------------------------

  def new_ticket(ticket)
    @ticket = ticket
    key = ticket.priority.to_s == 'urgent' ? 'new_ticket_urgent' : 'new_ticket'
    operator_mail(ticket, [support_alias], subject_for(ticket, key))
  end

  def customer_replied(ticket, message)
    @ticket = ticket
    @message = message
    operator_mail(ticket, [assignee_email(ticket) || support_alias], subject_for(ticket, 'customer_replied'))
  end

  # The assignee AND the alias: a breach is the one event the desk as a whole has to see, not only whoever
  # happens to hold the ticket.
  def sla_breached(ticket, event_type)
    @ticket = ticket
    @event_type = event_type
    operator_mail(ticket, [assignee_email(ticket), support_alias], subject_for(ticket, event_type))
  end

  private

  # The account's locale decides the customer's language, through `ApplicationMailer#switch_locale`, which
  # reads `Current.account`. Operator mail deliberately does not set it: it is Lynomia's own mail and belongs
  # in the installation's default locale, not the customer's.
  def customer_mail(ticket, recipients, subject)
    to = recipients.compact_blank.uniq
    return if to.empty?

    ensure_current_account(ticket.account)
    mail(to: to, subject: subject)
  end

  def operator_mail(ticket, recipients, subject)
    to = recipients.compact_blank.uniq
    return refuse_without_operator_recipient(ticket) if to.empty?

    mail(to: to, subject: subject)
  end

  # THE GAP, MADE VISIBLE. No alias is configured and no assignee holds the ticket, so there is nobody to tell
  # -- and inventing an address is the one thing this must not do. An operator reads this line in the same log
  # stream as every other operator signal, and the staff desk renders the same answer from
  # `PlatformSupport::SupportAlias.configured?`.
  def refuse_without_operator_recipient(ticket)
    Lynomia::OperatorLog.error(
      'PLATFORM_SUPPORT_OPERATOR_MAIL_UNDELIVERABLE',
      ticket: ticket.id, reference: ticket.reference, alias_configured: PlatformSupport::SupportAlias.configured?
    )
    nil
  end

  def support_alias
    PlatformSupport::SupportAlias.configured? ? PlatformSupport::SupportAlias.address! : nil
  end

  # The reporter's address is read from the live user row and nowhere else. `platform_support_tickets` holds
  # `reporter_name` and deliberately NEVER `reporter_email` (D-4), so a deleted user has no address here --
  # which is the point.
  def reporter_email(ticket)
    ticket.reporter&.email
  end

  def customer_recipients(ticket)
    [reporter_email(ticket), *ticket.account&.administrators&.pluck(:email)]
  end

  def assignee_email(ticket)
    ticket.assignee&.user&.email
  end

  def subject_for(ticket, key)
    I18n.t("platform_support.mailer.#{key}.subject", reference: ticket.reference, subject: ticket.subject)
  end

  # The tenant surface, at the frontend route the collision table reserves for this module (§9). No
  # documentation URL and no brand string is hard-coded here; the layout supplies the branding.
  def ticket_url(ticket)
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{ticket.account_id}/help/tickets/#{ticket.id}"
  end

  def staff_ticket_url(ticket)
    "#{ENV.fetch('FRONTEND_URL', nil)}/super_admin/platform_support/tickets/#{ticket.id}"
  end
end
