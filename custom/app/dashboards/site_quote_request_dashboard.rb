# frozen_string_literal: true

require 'administrate/base_dashboard'

# Quote requests from the public pricing page, for the operator who answers them.
#
# NO `new` AND NO CREATE FORM. These records are written by visitors; an operator-created one would be a row
# nobody sent. What an operator needs is to read them, mark where each has got to, and delete spam -- so
# `status` is the only editable attribute.
#
# `notification_attempted_at` and `notification_error` are shown and NOT editable: they are what
# Marketing::QuoteNotificationJob recorded about the alert for this row, and an operator editing them would be
# editing the installation's own account of what happened.
class SiteQuoteRequestDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String.with_options(searchable: true),
    email: Field::String.with_options(searchable: true),
    company: Field::String.with_options(searchable: true),
    phone: Field::String,
    team_size: Field::String,
    channels: Field::String,
    message: Field::Text,
    locale: Field::String,
    status: Field::Select.with_options(collection: SiteQuoteRequest.statuses.keys),
    notification_attempted_at: Field::DateTime,
    notification_error: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id created_at name company email status].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id created_at name email company phone team_size channels locale message status
    notification_attempted_at notification_error updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[status].freeze

  COLLECTION_FILTERS = {
    unanswered: ->(resources) { resources.where(status: :new_request) },
    # The leads whose alert never got out, so the operator knows which ones nobody was told about.
    notification_failed: ->(resources) { resources.notification_failed }
  }.freeze

  def display_resource(quote)
    "##{quote.id} #{quote.name}"
  end
end
