/* global axios */

import ApiClient from './ApiClient';

// Lynomia WhatsApp Template Manager (docs/whatsapp-template-manager/02-local-record-design.md): the templates an
// account manages -- local drafts and the mirror of what Meta holds -- with the inboxes that can send each one and
// what may be done to it. The per-inbox inboxes/:id/message_templates endpoint is unchanged and still serves the
// composer, the campaign form and the mobile app.
class WhatsAppTemplatesAPI extends ApiClient {
  constructor() {
    super('whatsapp/message_templates', { accountScoped: true });
  }

  get(config = {}) {
    return axios.get(this.url, config);
  }

  submit(id) {
    return axios.post(`${this.url}/${id}/submit`);
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }
}

export default new WhatsAppTemplatesAPI();
