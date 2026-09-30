// Formatting and safety helpers for the Lynomia Commerce panel. Orders arrive already normalized by the backend.

export const ORDER_LIMIT = 5;
export const MINUTE_MS = 60 * 1000;

// Only absolute https links without credentials are opened or sent to a customer.
export const safeHttpsUrl = url => {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password) {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
};

// The admin order URL is built by the backend from the store URL an administrator connected; development stores on
// the trusted-host policy may be plain http.
export const safeAdminUrl = url => {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    if (!['https:', 'http:'].includes(parsed.protocol) || parsed.username) {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
};

export const formatAmount = (amount, currency, locale) => {
  const value = Number(amount);
  if (Number.isNaN(value)) return `${amount} ${currency}`;
  try {
    return new Intl.NumberFormat(locale, {
      style: 'currency',
      currency,
    }).format(value);
  } catch {
    return `${amount} ${currency}`;
  }
};

export const formatDate = (isoDate, locale) => {
  if (!isoDate) return '';
  return new Intl.DateTimeFormat(locale, { dateStyle: 'medium' }).format(
    new Date(isoDate)
  );
};

export const relativeTime = (isoDate, locale, now = Date.now()) => {
  const minutes = Math.max(
    0,
    Math.round((now - new Date(isoDate).getTime()) / MINUTE_MS)
  );
  const formatter = new Intl.RelativeTimeFormat(locale, { numeric: 'auto' });
  if (minutes < 60) return formatter.format(-minutes, 'minute');
  return formatter.format(-Math.round(minutes / 60), 'hour');
};

export const hasTracking = order =>
  !!(order.tracking?.number || safeHttpsUrl(order.tracking?.url));

export const trackingMessage = (order, t) => {
  const url = safeHttpsUrl(order.tracking?.url);
  const number = order.tracking?.number;
  if (number && url) {
    return t('COMMERCE.PANEL.TRACKING_MESSAGE.FULL', {
      orderNumber: order.order_number,
      number,
      url,
    });
  }
  if (url) {
    return t('COMMERCE.PANEL.TRACKING_MESSAGE.URL', {
      orderNumber: order.order_number,
      url,
    });
  }
  return t('COMMERCE.PANEL.TRACKING_MESSAGE.NUMBER', {
    orderNumber: order.order_number,
    number,
  });
};
