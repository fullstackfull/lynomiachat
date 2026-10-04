// Lynomia Contacts, phase B2 (docs/contacts/03-phase-b.md). The server has always sent the real reason a
// contact write failed, and the store already attaches it to the exception it throws. Five call sites then
// discarded it and showed a canned "already in use" line instead, or nothing at all when the invalid
// attribute was neither `email` nor `phone_number` — which is how an e164 format rejection came out as "this
// phone number is in use for another contact".
//
// The server now also sends the validator that rejected each field (`RequestExceptionHandler`'s `error_types`),
// so the client can tell those two apart on the same field and show its own localized sentence. The server's
// own message is the fallback: it is only ever English, because the two Contact validators build their
// message with `I18n.t` in the class body, which freezes it at class-load time.

import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';

// (attribute, validator) -> our own string. Anything not listed falls back to the server's wording, so a new
// validation shows up as real text rather than disappearing.
const LOCALIZED_ERRORS = {
  phone_number: {
    taken: 'CONTACT_ERRORS.PHONE_NUMBER.TAKEN',
    invalid: 'CONTACT_ERRORS.PHONE_NUMBER.INVALID',
  },
  email: {
    taken: 'CONTACT_ERRORS.EMAIL.TAKEN',
    invalid: 'CONTACT_ERRORS.EMAIL.INVALID',
  },
  identifier: { taken: 'CONTACT_ERRORS.IDENTIFIER.TAKEN' },
  labels: { not_in_account: 'CONTACT_ERRORS.LABELS.NOT_IN_ACCOUNT' },
};

const firstOf = value => [].concat(value ?? [])[0];

/**
 * The per-field messages to show for a failed contact write, localized where we have our own wording.
 * @param {Error} error - What `contacts/create` or `contacts/update` threw.
 * @param {Function} t - The `vue-i18n` translate function.
 * @returns {Object} Attribute name to message, e.g. `{ phone_number: '…' }`. Empty when the failure carried
 *   no field-level validation errors.
 */
export const contactFieldErrors = (error, t) => {
  const fieldErrors = error?.fieldErrors;
  if (!fieldErrors) return {};

  return Object.entries(fieldErrors).reduce(
    (messages, [attribute, serverMessages]) => {
      const type = firstOf(error.fieldErrorTypes?.[attribute]);
      const key = LOCALIZED_ERRORS[attribute]?.[type];
      const message = key ? t(key) : firstOf(serverMessages);
      if (message) messages[attribute] = message;
      return messages;
    },
    {}
  );
};

/**
 * The one message to show for a failed contact write. Never empty, so no path can fail silently.
 * @param {Error} error - What the store threw.
 * @param {Function} t - The `vue-i18n` translate function.
 * @returns {string} A field message when exactly one field failed, otherwise the server's own summary, and
 *   the generic sentence when the failure carried no message at all.
 */
export const contactErrorMessage = (error, t) => {
  const fieldMessages = Object.values(contactFieldErrors(error, t));
  if (fieldMessages.length === 1) return fieldMessages[0];

  if (error instanceof DuplicateContactException) {
    return error.contactErrorDetail || t('CONTACT_ERRORS.GENERIC');
  }
  if (error instanceof ExceptionWithMessage) {
    return error.data || t('CONTACT_ERRORS.GENERIC');
  }
  // Anything else is a transport or server failure, whose raw text is not for the user.
  return t('CONTACT_ERRORS.GENERIC');
};

/**
 * The identity fields a failed write says are already in use, which are the ones the create dialog can offer
 * a way out of. Keyed off the validator, not the attribute name: `phone_number` carries both a uniqueness and
 * a format rule, and only the first means another contact holds this value.
 * @param {Error} error - What the store threw.
 * @returns {string[]} The attribute names, e.g. `['phone_number']`.
 */
export const takenIdentityFields = error =>
  Object.entries(error?.fieldErrorTypes ?? {})
    .filter(
      ([attribute, types]) =>
        ['phone_number', 'email', 'identifier'].includes(attribute) &&
        [].concat(types ?? []).includes('taken')
    )
    .map(([attribute]) => attribute);
