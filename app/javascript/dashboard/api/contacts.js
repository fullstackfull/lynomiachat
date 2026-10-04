/* global axios */
import ApiClient from './ApiClient';

/**
 * The body of an import or of its preview. The two take exactly the same payload, so whatever the preview
 * classified is what the import then performs (docs/contacts/04-bulk-import.md).
 * @param {Object} payload - `{ file, phoneNumbers, labels, defaultCountry, duplicatePolicy }`.
 * @returns {FormData} The multipart body. A file and pasted numbers are alternatives; the file wins.
 */
export const buildImportFormData = ({
  file,
  phoneNumbers = '',
  labels = [],
  defaultCountry = '',
  duplicatePolicy = '',
} = {}) => {
  const formData = new FormData();
  if (file) {
    formData.append('import_file', file);
  } else if (phoneNumbers) {
    formData.append('phone_numbers', phoneNumbers);
  }
  labels.forEach(label => formData.append('labels[]', label));
  if (defaultCountry) formData.append('default_country', defaultCountry);
  if (duplicatePolicy) formData.append('duplicate_policy', duplicatePolicy);
  return formData;
};

export const buildContactParams = (page, sortAttr, label, search) => ({
  include_contact_inboxes: false,
  page,
  sort: sortAttr,
  ...(search ? { q: search } : {}),
  ...(label ? { labels: [label] } : {}),
});

const normalizeImportPayload = payload =>
  payload instanceof File || payload instanceof Blob
    ? { file: payload }
    : payload;

class ContactAPI extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  get(page, sortAttr = 'name', label = '') {
    return axios.get(this.url, {
      params: buildContactParams(page, sortAttr, label, ''),
    });
  }

  show(id) {
    return axios.get(`${this.url}/${id}?include_contact_inboxes=false`);
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}?include_contact_inboxes=false`, data);
  }

  getConversations(contactId, { inboxId, conversationId } = {}) {
    const params = {};
    if (inboxId) params.inbox_id = inboxId;
    if (conversationId) params.conversation_id = conversationId;
    return axios.get(`${this.url}/${contactId}/conversations`, { params });
  }

  getAttachments(contactId, page = 1) {
    return axios.get(`${this.url}/${contactId}/attachments`, {
      params: { page },
    });
  }

  getContactableInboxes(contactId) {
    return axios.get(`${this.url}/${contactId}/contactable_inboxes`);
  }

  getContactLabels(contactId) {
    return axios.get(`${this.url}/${contactId}/labels`);
  }

  initiateCall(contactId, inboxId, conversationId = null) {
    return axios.post(`${this.url}/${contactId}/call`, {
      inbox_id: inboxId,
      conversation_id: conversationId,
    });
  }

  updateContactLabels(contactId, labels) {
    return axios.post(`${this.url}/${contactId}/labels`, { labels });
  }

  search(search = '', page = 1, sortAttr = 'name', label = '', options = {}) {
    return axios.get(`${this.url}/search`, {
      params: buildContactParams(page, sortAttr, label, search),
      signal: options.signal,
    });
  }

  active(page = 1, sortAttr = 'name') {
    return axios.get(`${this.url}/active`, {
      params: buildContactParams(page, sortAttr),
    });
  }

  // eslint-disable-next-line default-param-last
  filter(page = 1, sortAttr = 'name', queryPayload) {
    return axios.post(`${this.url}/filter`, queryPayload, {
      params: buildContactParams(page, sortAttr),
    });
  }

  importContacts(payload) {
    // A bare File keeps the old single-argument contract working.
    const body =
      payload instanceof FormData
        ? payload
        : buildImportFormData(normalizeImportPayload(payload));
    return axios.post(`${this.url}/import`, body, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  previewImport(payload) {
    return axios.post(
      `${this.url}/import_preview`,
      buildImportFormData(normalizeImportPayload(payload)),
      {
        headers: { 'Content-Type': 'multipart/form-data' },
      }
    );
  }

  destroyCustomAttributes(contactId, customAttributes) {
    return axios.post(`${this.url}/${contactId}/destroy_custom_attributes`, {
      custom_attributes: customAttributes,
    });
  }

  destroyAvatar(contactId) {
    return axios.delete(`${this.url}/${contactId}/avatar`);
  }

  exportContacts(queryPayload) {
    return axios.post(`${this.url}/export`, queryPayload);
  }
}

export default new ContactAPI();
