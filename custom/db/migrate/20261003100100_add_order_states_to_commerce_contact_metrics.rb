# Lynomia Automation's Commerce triggers (docs/automation/04-commerce-triggers.md): per visible order of the link's last
# read, a hashed order id and its normalized status, payment status, shipment statuses and creation time, so the next
# read can tell what changed. Never order data. NULL until the first read after this migration (the baseline).
class AddOrderStatesToCommerceContactMetrics < ActiveRecord::Migration[7.2]
  def change
    add_column :commerce_contact_metrics, :order_states, :jsonb
  end
end
