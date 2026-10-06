const FALLBACK_LOCALE = 'en';

function isSupported(tag) {
  if (!tag) return false;

  try {
    return Intl.NumberFormat.supportedLocalesOf([tag]).length > 0;
  } catch {
    // RangeError: the tag is not well-formed, which is exactly the case this helper exists for.
    return false;
  }
}

/**
 * Makes a locale tag safe to hand to an Intl constructor.
 *
 * Intl throws a RangeError on a tag that is not structurally valid BCP 47, and the tags this dashboard formats
 * with do not all come from inside it: `navigator.language` is derived by the browser from the host, and can
 * arrive as something Intl refuses -- Chromium on a POSIX host reports `en-US@posix`. A date or a number is not
 * worth a component crash, so an unusable tag degrades to the next best thing instead: the base language if Intl
 * knows it, otherwise English.
 *
 * @param {string} tag - a locale tag, from the app's own i18n or from the browser
 * @param {string} [fallback] - what to use when nothing in the tag is usable
 * @returns {string} a tag Intl accepts
 */
export function toIntlLocale(tag, fallback = FALLBACK_LOCALE) {
  if (!tag) return fallback;

  // Underscores are what a Rails-side locale looks like (pt_BR); Intl wants hyphens.
  const normalized = String(tag).replace(/_/g, '-');

  if (isSupported(normalized)) return normalized;

  const base = normalized.split(/[-@.]/)[0];
  return isSupported(base) ? base : fallback;
}
