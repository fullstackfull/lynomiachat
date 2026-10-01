# Lynomia Audience: what the orders Lynomia last read for one customer link add up to (docs/audience/03-commerce-query-model.md),
# so audience conditions run in SQL without calling a store. The figures follow Customer 360's rules
# (Commerce::Customer360) over the same orders the panel shows: the store's latest ConversationPanel::ORDER_LIMIT, so
# they are "visible", never lifetime figures.
#
# Written only by .record, from the order reads that already exist (an agent's Commerce section and the realtime
# refresh): no read of its own. A link without a row has not been read yet: unknown, never zero. The row goes with its
# link, and is dropped when the link is removed (suppressed) or points to another store customer.
class Commerce::ContactMetric < ApplicationRecord
  self.table_name = 'commerce_contact_metrics'

  belongs_to :account
  belongs_to :customer_link, class_name: 'Commerce::CustomerLink', foreign_key: :commerce_customer_link_id, inverse_of: :contact_metric

  # `result` is the Commerce::Cache result of reading the link's orders. Only a new read changes the row: a cache hit or
  # a stale fallback carries the time of the read it came from, so writing it again changes nothing.
  def self.record(link, result)
    fetched_at = Time.iso8601(result.fetched_at)
    metric = find_or_initialize_by(commerce_customer_link_id: link.id)
    return if metric.persisted? && metric.fetched_at >= fetched_at

    metric.update!(account_id: link.account_id, fetched_at: fetched_at, **figures(result.value))
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.figures(orders)
    {
      orders_count: orders.size,
      active_orders_count: Commerce::Customer360.active_orders_count(orders),
      last_purchase_at: Commerce::Customer360.last_purchase_at(orders),
      spend: Commerce::Customer360.spend(orders).to_h { |total| [total[:currency], total[:amount]] },
      order_statuses: orders.filter_map { |order| order['status'] }.uniq.sort,
      payment_statuses: orders.filter_map { |order| order['payment_status'] }.uniq.sort,
      shipment_statuses: orders.flat_map { |order| Array(order['shipments']).filter_map { |shipment| shipment['status'] } }.uniq.sort
    }
  end

  private_class_method :figures
end
