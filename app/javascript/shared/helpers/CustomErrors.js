/* eslint-disable max-classes-per-file */
export class DuplicateContactException extends Error {
  static DEFAULT_MESSAGE = 'DUPLICATE_CONTACT';

  constructor(data) {
    super(DuplicateContactException.DEFAULT_MESSAGE);
    this.data = data;
    this.name = 'DuplicateContactException';
    /** Attribute name -> the server's messages for it, from the 422 `errors` map. */
    this.fieldErrors = {};
    /** Attribute name -> the validators that rejected it (`taken`, `invalid`, …), from `error_types`. */
    this.fieldErrorTypes = {};
  }

  /** Server or client may assign `message` after construction; otherwise still DEFAULT_MESSAGE. */
  get contactErrorDetail() {
    return this.message === DuplicateContactException.DEFAULT_MESSAGE
      ? null
      : this.message;
  }
}
export class ExceptionWithMessage extends Error {
  constructor(data) {
    super('ERROR_WITH_MESSAGE');
    this.data = data;
    this.name = 'ExceptionWithMessage';
  }
}
