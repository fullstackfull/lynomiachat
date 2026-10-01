# Control runner for the Audience E2E (docs/audience/05-performance.md §E2E). Run with `rails runner`.
#
#   setup <ck> <cs>   Lynomia Demo A: Commerce on, English, no stores, no saved contact audiences; the disposable local
#                     WooCommerce test store A1 connected with its Read key (nothing is written to it); a Salla store with
#                     a summary that must never count (Salla stays switched off); Layla linked in A1 but never read
#                     (unknown); reports ids
#   summaries         the account's audience summaries: contact names, counts, currencies, statuses (no other data)
#   audiences         the saved contact audiences of the account: names and conditions
#   teardown          the stores (their links and summaries go with them) and the saved contact audiences removed
require 'json'

def report(result) = puts("SIM #{result.to_json}")

def account_a = Account.find_by!(name: 'Lynomia Demo A')

def admin_a = User.find_by!(email: 'admin_a@commerce.lynomia.local')

def conversation_of(name) = account_a.conversations.joins(:contact).find_by!(contacts: { name: name })

def clean
  account_a.commerce_stores.find_each(&:destroy!)
  Commerce::Store.where(base_url: 'http://localhost:8081').find_each(&:destroy!)
  account_a.custom_filters.contact.delete_all
end

case ARGV[0]
when 'setup'
  clean
  account_a.update!(locale: 'en')
  account_a.enable_features!('lynomia_commerce', 'crm')
  store = Commerce::StoreConnection.new(account: account_a, user: admin_a)
                                   .connect(provider: 'woocommerce', base_url: 'http://localhost:8081', name: 'Syria Cosmetics',
                                            credentials: { 'consumer_key' => ARGV[1], 'consumer_secret' => ARGV[2] })
  salla = account_a.commerce_stores.create!(provider: 'salla', name: 'Salla (switched off)', base_url: 'https://salla.sa/e2e-audience',
                                            external_store_id: '990000001', credentials: { 'access_token' => 'unused' })
  # Linked in A1 but never read: its orders are unknown (never zero) until someone opens its conversation.
  Commerce::CustomerLink.create!(account: account_a, store: store, contact: conversation_of('ليلى حداد').contact,
                                 external_customer_id: 'e2e-unread', match_source: :manual)
  hana = conversation_of('Hana Saeed').contact
  link = Commerce::CustomerLink.create!(account: account_a, store: salla, contact: hana, external_customer_id: 'e2e-hana', match_source: :manual)
  Commerce::ContactMetric.create!(account: account_a, customer_link: link, orders_count: 9, active_orders_count: 0,
                                  spend: { 'SAR' => '99999.00' }, fetched_at: Time.current)
  report({ account_id: account_a.id, store_id: store.id, salla_enabled: Commerce::Providers.enabled?('salla'),
           conversations: ['Omar Khalil', 'Sara Ali', 'Hana Saeed'].to_h { |name| [name, conversation_of(name).display_id] },
           account_b_id: Account.find_by!(name: 'Lynomia Demo B').id })
when 'summaries'
  rows = Commerce::ContactMetric.where(account: account_a).includes(customer_link: %i[contact store]).map do |metric|
    { contact: metric.customer_link.contact.name, provider: metric.customer_link.store.provider, orders: metric.orders_count,
      spend: metric.spend, last_purchase_at: metric.last_purchase_at&.iso8601, order_statuses: metric.order_statuses }
  end
  report({ summaries: rows })
when 'audiences'
  report({ audiences: account_a.custom_filters.contact.map { |filter| { id: filter.id, name: filter.name, query: filter.query } } })
when 'teardown'
  clean
  report({ stores: account_a.commerce_stores.count, audiences: account_a.custom_filters.contact.count })
end
