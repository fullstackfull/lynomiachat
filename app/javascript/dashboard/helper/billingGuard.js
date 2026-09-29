// Billing customization (see BILLING_CHANGES.md)
// When the API answers 402 "subscription_required", send the user to the
// subscription page of that account.
const SUBSCRIPTION_PATH = '/settings/subscription';
let isRedirecting = false;

export const handleBillingLock = error => {
  const { response, config } = error || {};
  if (response?.status !== 402) return;
  if (response?.data?.error !== 'subscription_required') return;
  if (isRedirecting || window.location.pathname.includes(SUBSCRIPTION_PATH)) return;

  const match = (config?.url || '').match(/accounts\/(\d+)\//);
  if (!match) return;

  isRedirecting = true;
  window.location.assign(`/app/accounts/${match[1]}${SUBSCRIPTION_PATH}`);
};