# Whether the operator was actually told about a quote request.
#
# WHY THE OUTCOME IS RECORDED ON THE ROW. The quote settings screen reports a "delivery problem" state, and the
# owner's requirement is explicit that it must be determinable RELIABLY rather than guessed -- so it cannot be
# inferred from the presence of an address. Nothing in the application recorded a mail outcome before this:
# `deliver_later` hands the message to ActiveJob and the result is logged and forgotten.
#
# TWO COLUMNS, ONE READING. `notification_attempted_at` is stamped when the job finishes an attempt, whatever
# the outcome, and `notification_error` holds the exception class and message when that attempt failed. So a
# row with an attempt and no error was delivered, a row with both was refused, and a row with neither has not
# been tried yet -- and the newest attempt of all is the installation's current delivery state, which is the
# one thing the settings screen has to get right.
class AddNotificationOutcomeToSiteQuoteRequests < ActiveRecord::Migration[7.0]
  def change
    add_column :site_quote_requests, :notification_attempted_at, :datetime
    add_column :site_quote_requests, :notification_error, :string

    # Serves both of the settings screen's queries: the newest attempt, and the newest successful one.
    add_index :site_quote_requests, :notification_attempted_at
  end
end
