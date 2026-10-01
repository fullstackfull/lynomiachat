import { useI18n } from 'vue-i18n';

// Maps the backend's Commerce codes (order/payment/shipment/store status, error codes, URL reasons, panel states) to their
// strings. Every key is written out so the i18n linter can check it; unknown codes fall back to a generic label.
export function useCommerceLabels() {
  const { t } = useI18n();

  const orderStatus = status =>
    ({
      pending: t('COMMERCE.ORDER_STATUS.PENDING'),
      processing: t('COMMERCE.ORDER_STATUS.PROCESSING'),
      on_hold: t('COMMERCE.ORDER_STATUS.ON_HOLD'),
      shipped: t('COMMERCE.ORDER_STATUS.SHIPPED'),
      delivered: t('COMMERCE.ORDER_STATUS.DELIVERED'),
      completed: t('COMMERCE.ORDER_STATUS.COMPLETED'),
      cancelled: t('COMMERCE.ORDER_STATUS.CANCELLED'),
      refunded: t('COMMERCE.ORDER_STATUS.REFUNDED'),
      failed: t('COMMERCE.ORDER_STATUS.FAILED'),
      draft: t('COMMERCE.ORDER_STATUS.DRAFT'),
    })[status] || t('COMMERCE.ORDER_STATUS.OTHER');

  const paymentStatus = status =>
    ({
      paid: t('COMMERCE.PAYMENT_STATUS.PAID'),
      unpaid: t('COMMERCE.PAYMENT_STATUS.UNPAID'),
      partially_paid: t('COMMERCE.PAYMENT_STATUS.PARTIALLY_PAID'),
      failed: t('COMMERCE.PAYMENT_STATUS.FAILED'),
      refunded: t('COMMERCE.PAYMENT_STATUS.REFUNDED'),
      partially_refunded: t('COMMERCE.PAYMENT_STATUS.PARTIALLY_REFUNDED'),
    })[status] || t('COMMERCE.PAYMENT_STATUS.UNKNOWN');

  const shipmentStatus = status =>
    ({
      pending: t('COMMERCE.SHIPMENT_STATUS.PENDING'),
      in_transit: t('COMMERCE.SHIPMENT_STATUS.IN_TRANSIT'),
      out_for_delivery: t('COMMERCE.SHIPMENT_STATUS.OUT_FOR_DELIVERY'),
      delivered: t('COMMERCE.SHIPMENT_STATUS.DELIVERED'),
      failed: t('COMMERCE.SHIPMENT_STATUS.FAILED'),
      cancelled: t('COMMERCE.SHIPMENT_STATUS.CANCELLED'),
      returned: t('COMMERCE.SHIPMENT_STATUS.RETURNED'),
    })[status] || t('COMMERCE.SHIPMENT_STATUS.OTHER');

  const errorMessage = code =>
    ({
      STORE_UNAVAILABLE: t('COMMERCE.ERRORS.STORE_UNAVAILABLE'),
      AUTH_INVALID: t('COMMERCE.ERRORS.AUTH_INVALID'),
      PERMISSION_DENIED: t('COMMERCE.ERRORS.PERMISSION_DENIED'),
      RATE_LIMITED: t('COMMERCE.ERRORS.RATE_LIMITED'),
      TIMEOUT: t('COMMERCE.ERRORS.TIMEOUT'),
      INVALID_RESPONSE: t('COMMERCE.ERRORS.INVALID_RESPONSE'),
      NOT_FOUND: t('COMMERCE.ERRORS.NOT_FOUND'),
      INVALID_STORE_URL: t('COMMERCE.ERRORS.INVALID_STORE_URL'),
      INVALID_QUERY: t('COMMERCE.ERRORS.INVALID_QUERY'),
      ENCRYPTION_NOT_CONFIGURED: t('COMMERCE.ERRORS.ENCRYPTION_NOT_CONFIGURED'),
      STORE_ALREADY_CONNECTED: t('COMMERCE.ERRORS.STORE_ALREADY_CONNECTED'),
      PROVIDER_DISABLED: t('COMMERCE.ERRORS.PROVIDER_DISABLED'),
      PROTECTED_DATA_NOT_APPROVED: t(
        'COMMERCE.ERRORS.PROTECTED_DATA_NOT_APPROVED'
      ),
    })[code] || t('COMMERCE.ERRORS.GENERIC');

  const urlError = reason =>
    ({
      invalid: t('COMMERCE.URL_ERRORS.INVALID'),
      https_required: t('COMMERCE.URL_ERRORS.HTTPS_REQUIRED'),
      port_not_allowed: t('COMMERCE.URL_ERRORS.PORT_NOT_ALLOWED'),
      ip_address_not_allowed: t('COMMERCE.URL_ERRORS.IP_ADDRESS_NOT_ALLOWED'),
      private_address: t('COMMERCE.URL_ERRORS.PRIVATE_ADDRESS'),
      redirect: t('COMMERCE.URL_ERRORS.REDIRECT'),
      shopify_domain: t('COMMERCE.URL_ERRORS.SHOPIFY_DOMAIN'),
    })[reason] || t('COMMERCE.ERRORS.INVALID_STORE_URL');

  // The message for a failed API call: `{ error: { code, reason } }` bodies from the Commerce API.
  const apiErrorMessage = error => {
    const { code, reason } = error?.response?.data?.error || {};
    if (code === 'INVALID_STORE_URL' && reason) return urlError(reason);
    if (reason === 'legacy_shopify_integration') {
      return t('COMMERCE.ERRORS.LEGACY_SHOPIFY_CONNECTED');
    }
    return errorMessage(code);
  };

  const providerName = provider =>
    ({
      woocommerce: t('COMMERCE.PROVIDERS.WOOCOMMERCE'),
      salla: t('COMMERCE.PROVIDERS.SALLA'),
      zid: t('COMMERCE.PROVIDERS.ZID'),
      shopify: t('COMMERCE.PROVIDERS.SHOPIFY'),
    })[provider] || provider;

  const storeStatus = status =>
    ({
      active: t('COMMERCE.SETTINGS.STATUS.ACTIVE'),
      disabled: t('COMMERCE.SETTINGS.STATUS.DISABLED'),
      needs_reauth: t('COMMERCE.SETTINGS.STATUS.NEEDS_REAUTH'),
      disconnected: t('COMMERCE.SETTINGS.STATUS.DISCONNECTED'),
    })[status] || status;

  const matchSource = source =>
    ({
      verified_phone: t('COMMERCE.PANEL.MATCH_SOURCE.VERIFIED_PHONE'),
      verified_email: t('COMMERCE.PANEL.MATCH_SOURCE.VERIFIED_EMAIL'),
      external_id: t('COMMERCE.PANEL.MATCH_SOURCE.EXTERNAL_ID'),
    })[source] || t('COMMERCE.PANEL.MATCH_SOURCE.MANUAL');

  const matchState = state =>
    ({
      not_found: t('COMMERCE.PANEL.NOT_FOUND'),
      suggested: t('COMMERCE.PANEL.SUGGESTED'),
      multiple: t('COMMERCE.PANEL.MULTIPLE'),
    })[state] || '';

  // A store's entry in Customer 360.
  const overviewState = state =>
    ({
      linked: t('COMMERCE.OVERVIEW.STATE.LINKED'),
      not_found: t('COMMERCE.OVERVIEW.STATE.NOT_LINKED'),
      suggested: t('COMMERCE.OVERVIEW.STATE.NOT_LINKED'),
      multiple: t('COMMERCE.OVERVIEW.STATE.NOT_LINKED'),
      needs_reauth: t('COMMERCE.OVERVIEW.STATE.NEEDS_REAUTH'),
      provider_unavailable: t('COMMERCE.OVERVIEW.STATE.PROVIDER_UNAVAILABLE'),
    })[state] || t('COMMERCE.OVERVIEW.STATE.UNAVAILABLE');

  return {
    orderStatus,
    paymentStatus,
    shipmentStatus,
    errorMessage,
    apiErrorMessage,
    urlError,
    providerName,
    storeStatus,
    matchSource,
    matchState,
    overviewState,
  };
}
