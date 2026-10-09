/* global axios */
import ApiClient from './ApiClient';

// One contact's activity timeline (docs/p8/03-contact-activity-timeline.md).
//
// Cursor-paged, never offset-paged: the server composes eight sources into one ordered list, so there is no
// stable page number to ask for. Each response carries the cursor for the next page, or none when the end is
// reached.
class ContactActivityAPI extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  get(contactId, { categories, cursor, limit } = {}, { signal } = {}) {
    return axios.get(`${this.url}/${contactId}/activity`, {
      params: { categories, cursor, limit },
      signal,
    });
  }
}

export default new ContactActivityAPI();
