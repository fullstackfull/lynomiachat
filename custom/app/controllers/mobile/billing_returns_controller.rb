# frozen_string_literal: true

# GET /mobile/billing/return?checkout=success|canceled|portal&account_id=123
#
# Stripe sends the customer here after paying from the mobile app.
# The page opens the app with the configured deep link, e.g.
#   lynomia://billing?checkout=success&account_id=123
# and shows a "Return to the app" button as a fallback.
# Plain public page: no dashboard session, locale or error handling needed.
class Mobile::BillingReturnsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  RESULTS = %w[success canceled portal].freeze
  STYLES = <<~CSS.squish.freeze
    body { font-family: -apple-system, system-ui, sans-serif; text-align: center; padding: 48px 24px; color: #1f2937; }
    .btn { display: inline-block; margin-top: 16px; padding: 12px 20px; border-radius: 10px; background: #2563eb; color: #fff; text-decoration: none; }
  CSS

  def show
    base = Billing::Settings.mobile_return_url
    return render(html: page(nil), layout: false) if base.blank?

    result = RESULTS.include?(params[:checkout]) ? params[:checkout] : 'success'
    query = { checkout: result, account_id: params[:account_id].to_s[/\A\d+\z/] }.compact.to_query
    separator = base.include?('?') ? '&' : '?'
    render html: page("#{base}#{separator}#{query}"), layout: false
  end

  private

  def page(deep_link)
    escaped = ERB::Util.html_escape(deep_link)
    script = deep_link ? "<script>window.location.replace(#{deep_link.to_json});</script>" : ''
    button = deep_link ? "<p><a class=\"btn\" href=\"#{escaped}\">العودة إلى التطبيق / Return to the app</a></p>" : ''

    <<~HTML.html_safe # rubocop:disable Rails/OutputSafety
      <!DOCTYPE html>
      <html lang="ar" dir="rtl">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Billing</title>
          <style>#{STYLES}</style>
        </head>
        <body>
          <h2>شكراً لك / Thank you</h2>
          <p>يمكنك الآن العودة إلى التطبيق.<br>You can now go back to the app.</p>
          #{button}
          #{script}
        </body>
      </html>
    HTML
  end
end
