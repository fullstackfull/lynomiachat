# Operator export for a Shopify customers/data_request (docs/commerce/20-shopify-webhooks-and-compliance.md §4).
# Prints, as JSON, what Lynomia Commerce holds about the customer of Shopify data request <data_request_id>: that
# customer's links in the store. Send the output to the merchant (the account's administrators) within 30 days.
#
# usage: bundle exec rails runner docs/commerce/ops/shopify_data_request_export.rb <data_request_id>
data_request_id = ARGV.fetch(0)
audit = Enterprise::AuditLog.where(comment: 'commerce.shopify.customer_data_requested')
                            .find_by!("audited_changes->>'data_request_id' = ?", data_request_id)
store = Commerce::Store.find_by(id: audit.auditable_id)
links = Commerce::CustomerLink.where(id: audit.audited_changes['customer_link_ids'])
puts JSON.pretty_generate(
  data_request_id: data_request_id, requested_at: audit.created_at, account_id: audit.associated_id,
  store: store && { name: store.name, shop: store.base_url },
  customer_links: links.map do |link|
    { customer: link.external_customer_id, contact_id: link.contact_id, match_source: link.match_source, linked_at: link.created_at,
      confirmed_by: link.confirmed_by&.email }
  end
)
