import {
  contactErrorMessage,
  contactFieldErrors,
  takenIdentityFields,
} from '../contactErrors';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';

// Stands in for vue-i18n: returns the key, so a test can tell "we chose our own string" from "we fell back
// to the server's".
const t = key => `t:${key}`;

const validationError = ({ message, errors, errorTypes }) => {
  const error = new DuplicateContactException(Object.keys(errors ?? {}));
  if (message) error.message = message;
  error.fieldErrors = errors ?? {};
  error.fieldErrorTypes = errorTypes ?? {};
  return error;
};

describe('contactErrors', () => {
  describe('contactFieldErrors', () => {
    it('uses our own string when the validator is one we have wording for', () => {
      const error = validationError({
        message: 'Phone number has already been taken',
        errors: { phone_number: ['Phone number has already been taken'] },
        errorTypes: { phone_number: ['taken'] },
      });

      expect(contactFieldErrors(error, t)).toEqual({
        phone_number: 't:CONTACT_ERRORS.PHONE_NUMBER.TAKEN',
      });
    });

    // The defect this whole phase exists for: a format rejection used to render as "already in use".
    it('tells a format rejection apart from a duplicate on the same field', () => {
      const error = validationError({
        message: 'Phone number should be in e164 format',
        errors: { phone_number: ['Phone number should be in e164 format'] },
        errorTypes: { phone_number: ['invalid'] },
      });

      expect(contactFieldErrors(error, t)).toEqual({
        phone_number: 't:CONTACT_ERRORS.PHONE_NUMBER.INVALID',
      });
    });

    it('falls back to the server wording for a validator we do not know', () => {
      const error = validationError({
        errors: { name: ['Name is too long (maximum is 255 characters)'] },
        errorTypes: { name: ['too_long'] },
      });

      expect(contactFieldErrors(error, t)).toEqual({
        name: 'Name is too long (maximum is 255 characters)',
      });
    });

    it('keeps every field when more than one was rejected', () => {
      const error = validationError({
        errors: {
          email: ['Email has already been taken'],
          phone_number: ['Phone number has already been taken'],
        },
        errorTypes: { email: ['taken'], phone_number: ['taken'] },
      });

      expect(contactFieldErrors(error, t)).toEqual({
        email: 't:CONTACT_ERRORS.EMAIL.TAKEN',
        phone_number: 't:CONTACT_ERRORS.PHONE_NUMBER.TAKEN',
      });
    });

    it('reads the label rejection the create endpoint can return', () => {
      const error = validationError({
        errors: { labels: ['Labels do not exist in this account: vip'] },
        errorTypes: { labels: ['not_in_account'] },
      });

      expect(contactFieldErrors(error, t)).toEqual({
        labels: 't:CONTACT_ERRORS.LABELS.NOT_IN_ACCOUNT',
      });
    });

    it('is empty for a failure that carried no field errors', () => {
      expect(contactFieldErrors(new Error('boom'), t)).toEqual({});
      expect(contactFieldErrors(undefined, t)).toEqual({});
    });
  });

  describe('contactErrorMessage', () => {
    it('shows the one field message when only one field was rejected', () => {
      const error = validationError({
        message: 'Phone number should be in e164 format',
        errors: { phone_number: ['Phone number should be in e164 format'] },
        errorTypes: { phone_number: ['invalid'] },
      });

      expect(contactErrorMessage(error, t)).toBe(
        't:CONTACT_ERRORS.PHONE_NUMBER.INVALID'
      );
    });

    it("shows the server's summary when several fields were rejected", () => {
      const error = validationError({
        message:
          'Email has already been taken, Phone number has already been taken',
        errors: {
          email: ['Email has already been taken'],
          phone_number: ['Phone number has already been taken'],
        },
        errorTypes: { email: ['taken'], phone_number: ['taken'] },
      });

      expect(contactErrorMessage(error, t)).toBe(
        'Email has already been taken, Phone number has already been taken'
      );
    });

    it('shows the message carried by a non-validation failure', () => {
      expect(
        contactErrorMessage(new ExceptionWithMessage('Account is suspended'), t)
      ).toBe('Account is suspended');
    });

    // No branch may be silent, which is what four of the five call sites used to be.
    it('is never empty', () => {
      expect(
        contactErrorMessage(new Error('AxiosError: Network Error'), t)
      ).toBe('t:CONTACT_ERRORS.GENERIC');
      expect(contactErrorMessage(undefined, t)).toBe(
        't:CONTACT_ERRORS.GENERIC'
      );
      expect(
        contactErrorMessage(new DuplicateContactException(['email']), t)
      ).toBe('t:CONTACT_ERRORS.GENERIC');
      expect(contactErrorMessage(new ExceptionWithMessage(''), t)).toBe(
        't:CONTACT_ERRORS.GENERIC'
      );
    });
  });

  describe('takenIdentityFields', () => {
    it('names the identity field another contact already holds', () => {
      const error = validationError({
        errors: { phone_number: ['Phone number has already been taken'] },
        errorTypes: { phone_number: ['taken'] },
      });

      expect(takenIdentityFields(error)).toEqual(['phone_number']);
    });

    // Keyed off the validator, not the attribute: phone_number carries a format rule too, and no existing
    // contact can be found for a malformed number.
    it('does not treat a format rejection as a duplicate', () => {
      const error = validationError({
        errors: { phone_number: ['Phone number should be in e164 format'] },
        errorTypes: { phone_number: ['invalid'] },
      });

      expect(takenIdentityFields(error)).toEqual([]);
    });

    it('names both when two identity keys collided', () => {
      const error = validationError({
        errors: {
          email: ['Email has already been taken'],
          phone_number: ['Phone number has already been taken'],
        },
        errorTypes: { email: ['taken'], phone_number: ['taken'] },
      });

      expect(takenIdentityFields(error).sort()).toEqual([
        'email',
        'phone_number',
      ]);
    });

    it('ignores a taken field that is not an identity key', () => {
      const error = validationError({
        errors: { name: ['Name has already been taken'] },
        errorTypes: { name: ['taken'] },
      });

      expect(takenIdentityFields(error)).toEqual([]);
    });

    it('is empty for a failure that carried no types', () => {
      expect(takenIdentityFields(new Error('boom'))).toEqual([]);
      expect(takenIdentityFields(undefined)).toEqual([]);
    });
  });
});
