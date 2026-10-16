# Quote requests from the public pricing page.
#
# WHY A TABLE AND NOT AN EMAIL. A `mailto:` is not a quote request form, and an email that fails to send is a
# lead nobody knows was lost. The row is the record: it is written first, shown in Super Admin, and the
# notification email is a convenience on top of it. That ordering is what makes an unconfigured notification
# address a missed alert rather than a missed customer.
#
# WHY NOT PLATFORM SUPPORT. That desk is for a signed-in customer raising a ticket with Lynomia
# (config/routes/platform_support.rb) and every path on it is account-scoped. A quote request comes from
# somebody who has no account yet, which is the entire point of it.
#
# NO IP ADDRESS AND NO USER AGENT are stored. The only purpose they could serve here is abuse forensics, and
# abuse is handled in middleware by a Rack::Attack throttle that needs no stored copy -- while an IP against a
# named individual is personal data this form has no reason to keep (the audit trail's own rule, which
# coarsens an address to a network, is the precedent).
class CreateSiteQuoteRequests < ActiveRecord::Migration[7.0]
  def change
    create_table :site_quote_requests do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :company
      t.string :phone
      t.string :team_size
      t.jsonb :channels, default: [], null: false
      t.text :message
      t.string :locale, null: false, default: 'ar'
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    # The operator's two queries: the unhandled ones first, and everything newest-first.
    add_index :site_quote_requests, [:status, :created_at]
  end
end
