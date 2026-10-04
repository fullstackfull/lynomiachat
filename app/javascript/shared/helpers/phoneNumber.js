// Lynomia Contacts, phase B4 (docs/contacts/03-phase-b.md). The dashboard's first phone helper: every other
// `parsePhoneNumber` call in the frontend is single-argument, so a local number never parses and the phone
// input falls back to concatenating a dial code onto whatever was typed — which is how "+965" plus "0551…"
// becomes "+9650551…" and the server rejects it as not E.164.
//
// The four Ruby implementations stay where they are. This is the browser-side counterpart of
// `Commerce::Phone.e164` and keeps that service's rule verbatim: an international number carries its own
// region, a local number is read only against an EXPLICIT region, and nothing is ever guessed.
//
// A region derived from the browser timezone (shared/components/PhoneInput/helper.js) is deliberately not
// explicit — it is a visible pre-fill in the country picker, not a statement about this contact.

import parsePhoneNumber from 'libphonenumber-js';

// What people actually paste: "+965 2220 1234", "(055) 512-3456", "0551.112.233". `\s` covers the
// non-breaking space; the bidirectional marks a copy out of an Arabic page carries, it does not.
const FORMATTING_CHARACTERS = /[\s()./\u200e\u200f-]/g;

/**
 * Removes the punctuation people type and turns an international `00` prefix into `+`.
 * @param {string|number} raw - A phone number in any formatting.
 * @returns {string} The same number with only digits and a possible leading `+`.
 */
export const stripPhoneFormatting = raw => {
  const cleaned = String(raw ?? '').replace(FORMATTING_CHARACTERS, '');
  return cleaned.startsWith('00') ? `+${cleaned.slice(2)}` : cleaned;
};

/**
 * The E.164 form of a number, or null when it cannot be known without guessing.
 * @param {string|number} raw - What the user typed, in any formatting.
 * @param {string|null} regionCode - An ISO 3166-1 alpha-2 code the user chose explicitly, or null.
 * @returns {string|null} E.164, or null when the number is invalid or its region is unknown.
 */
export const toE164 = (raw, regionCode = null) => {
  const cleaned = stripPhoneFormatting(raw);
  if (!cleaned) return null;

  // A local number without an explicit region is ambiguous, and an ambiguous number is not normalized.
  if (!cleaned.startsWith('+') && !regionCode) return null;

  const parsed = cleaned.startsWith('+')
    ? parsePhoneNumber(cleaned)
    : parsePhoneNumber(cleaned, regionCode);

  return parsed?.isValid() ? parsed.number : null;
};

/**
 * Whether what was typed looks like a trunk-prefixed local number that no explicit region can resolve.
 * `00…` is already international by the time it gets here, so it is never flagged.
 * @param {string|number} raw - What the user typed.
 * @param {string|null} regionCode - The explicitly chosen region, or null.
 * @returns {boolean} True when the number needs a country before it can be understood.
 */
export const hasUnresolvedTrunkPrefix = (raw, regionCode = null) =>
  !regionCode && stripPhoneFormatting(raw).startsWith('0');
