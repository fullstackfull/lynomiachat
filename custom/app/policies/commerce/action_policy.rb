# Who may act on a store order from a conversation (docs/commerce/32-actions-security.md §permissions). Viewing Commerce
# and preparing a recovery message only need the conversation; actions need more:
#
#   manage_orders  status changes and resending the store's emails: administrators, and agents whose custom role grants
#                  `commerce_order_manage`
#   cancel/refund  administrators only (pilot): never granted to agents by a custom role
class Commerce::ActionPolicy < ApplicationPolicy
  MANAGE_PERMISSION = 'commerce_order_manage'.freeze
  RULES = {
    'update_order_status' => :manage_orders?, 'resend_invoice' => :manage_orders?, 'resend_payment_link' => :manage_orders?,
    'update_shipping' => :manage_orders?, 'cancel_order' => :cancel?, 'refund_full' => :refund?, 'refund_partial' => :refund?
  }.freeze

  # `record` is the action type.
  def perform?
    public_send(RULES.fetch(record))
  end

  def manage_orders?
    @account_user.administrator? || @account_user.permissions.include?(MANAGE_PERMISSION)
  end

  def cancel?
    @account_user.administrator?
  end

  def refund?
    @account_user.administrator?
  end
end
