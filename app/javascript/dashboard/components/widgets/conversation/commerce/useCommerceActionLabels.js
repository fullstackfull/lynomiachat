import { useI18n } from 'vue-i18n';

// Strings for order actions (docs/commerce/28-commerce-actions-architecture.md): action types, why an action is not
// available, and the reason codes the backend accepts. Every key is written out so the i18n linter can check it.
export function useCommerceActionLabels() {
  const { t } = useI18n();

  const actionLabel = type =>
    ({
      update_order_status: t('COMMERCE.ACTIONS.TYPES.UPDATE_ORDER_STATUS'),
      cancel_order: t('COMMERCE.ACTIONS.TYPES.CANCEL_ORDER'),
      refund_full: t('COMMERCE.ACTIONS.TYPES.REFUND_FULL'),
      refund_partial: t('COMMERCE.ACTIONS.TYPES.REFUND_PARTIAL'),
      resend_invoice: t('COMMERCE.ACTIONS.TYPES.RESEND_INVOICE'),
      resend_payment_link: t('COMMERCE.ACTIONS.TYPES.RESEND_PAYMENT_LINK'),
      update_shipping: t('COMMERCE.ACTIONS.TYPES.UPDATE_SHIPPING'),
    })[type] || type;

  const unavailableReason = reason =>
    ({
      permission_denied: t('COMMERCE.ACTIONS.UNAVAILABLE.PERMISSION_DENIED'),
      action_in_progress: t('COMMERCE.ACTIONS.UNAVAILABLE.ACTION_IN_PROGRESS'),
      paid_refund_first: t('COMMERCE.ACTIONS.UNAVAILABLE.PAID_REFUND_FIRST'),
      already_cancelled: t('COMMERCE.ACTIONS.UNAVAILABLE.ALREADY_CANCELLED'),
      not_paid: t('COMMERCE.ACTIONS.UNAVAILABLE.NOT_PAID'),
      nothing_refundable: t('COMMERCE.ACTIONS.UNAVAILABLE.NOTHING_REFUNDABLE'),
      order_state: t('COMMERCE.ACTIONS.UNAVAILABLE.ORDER_STATE'),
      no_email: t('COMMERCE.ACTIONS.UNAVAILABLE.NO_EMAIL'),
      unsupported: t('COMMERCE.ACTIONS.UNAVAILABLE.UNSUPPORTED'),
    })[reason] || t('COMMERCE.ACTIONS.UNAVAILABLE.OTHER');

  const refundReasons = [
    {
      value: 'customer_request',
      label: t('COMMERCE.ACTIONS.REFUND_REASONS.CUSTOMER_REQUEST'),
    },
    {
      value: 'duplicate',
      label: t('COMMERCE.ACTIONS.REFUND_REASONS.DUPLICATE'),
    },
    { value: 'damaged', label: t('COMMERCE.ACTIONS.REFUND_REASONS.DAMAGED') },
    {
      value: 'not_received',
      label: t('COMMERCE.ACTIONS.REFUND_REASONS.NOT_RECEIVED'),
    },
    { value: 'other', label: t('COMMERCE.ACTIONS.REFUND_REASONS.OTHER') },
  ];

  const cancelReasons = [
    {
      value: 'customer_request',
      label: t('COMMERCE.ACTIONS.CANCEL_REASONS.CUSTOMER_REQUEST'),
    },
    {
      value: 'inventory',
      label: t('COMMERCE.ACTIONS.CANCEL_REASONS.INVENTORY'),
    },
    { value: 'fraud', label: t('COMMERCE.ACTIONS.CANCEL_REASONS.FRAUD') },
    {
      value: 'payment_declined',
      label: t('COMMERCE.ACTIONS.CANCEL_REASONS.PAYMENT_DECLINED'),
    },
    { value: 'other', label: t('COMMERCE.ACTIONS.CANCEL_REASONS.OTHER') },
  ];

  return { actionLabel, unavailableReason, refundReasons, cancelReasons };
}
