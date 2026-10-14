# The one email the public pricing form sends: a notification to the operator.
#
# NOTHING IS SENT TO THE VISITOR. An automatic "we received your request" from an address nobody monitors is
# the kind of fake interaction this rebuild exists to remove; the page itself confirms the submission, and the
# reply the visitor gets comes from a person.
#
# RETURNING WITHOUT CALLING `mail` yields an ActionMailer::Base::NullMail, so `deliver_later` on a refused
# message is a no-op -- that is the mechanism behind "an installation with no address configured sends
# nothing", rather than a guard that raises on a request the visitor cannot do anything about.
#
# ApplicationMailer already installs `rescue_from(*ExceptionList::SMTP_EXCEPTIONS)`, so a relay failure is
# logged and does not fail the request that saved the row.
class Marketing::QuoteMailer < ApplicationMailer
  self.mailer_name = 'marketing_quote_mailer'

  def new_request(quote)
    return unless Marketing::QuoteNotification.configured?

    @quote = quote
    # The visitor's name is not in the subject: a subject line is logged and forwarded in places a body is
    # not, and the id is enough to find the row.
    mail(to: Marketing::QuoteNotification.address,
         subject: "New quote request ##{quote.id} from the website",
         reply_to: quote.email)
  end

  # The "send test email" button on the quote settings screen.
  #
  # It goes to the configured address and nowhere else, so what it proves is the thing an operator actually
  # wants proved: that THIS installation can deliver mail to THAT address. No `reply_to`, because there is no
  # sender to reply to -- the operator who pressed the button is named in the body instead, so somebody
  # receiving an unexpected test can see who ran it.
  def test_notification(requested_by)
    return unless Marketing::QuoteNotification.configured?

    @requested_by = requested_by
    @address = Marketing::QuoteNotification.address
    mail(to: @address, subject: t('marketing.quote_mailer.test_subject'))
  end
end
