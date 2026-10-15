/* global axios */

import ApiClient from './ApiClient';

class CampaignsAPI extends ApiClient {
  constructor() {
    super('campaigns', { accountScoped: true });
  }

  analyticsMetrics(id) {
    return axios.get(`${this.url}/${id}/analytics/metrics`);
  }

  // Lynomia: how many contacts these recipients select now (docs/campaigns/05-preview-and-dedup.md).
  // THE PREVIEW ASKS THE SEND'S QUESTION, WHICH MEANS IT NEEDS THE SEND'S SCOPE.
  //
  // The count is filtered by consent, and what consent is required depends on the CHANNEL a
  // partner grant was taken for and on whether the campaign is transactional -- which the
  // server reads from the template's category in the channel's own synced list. Sending
  // only the audience made every preview answer as SMS and as promotional, so a WhatsApp
  // UTILITY campaign was previewed against a grant requirement its send does not have and
  // the merchant was shown a number smaller than the one the campaign reaches. Both are
  // optional on the server: a caller previewing an audience rather than a specific campaign
  // legitimately knows neither.
  audiencePreview(audience, { signal, inboxId, templateParams } = {}) {
    const payload = { audience };
    if (inboxId) payload.inbox_id = inboxId;
    if (templateParams) payload.template_params = templateParams;

    return axios.post(`${this.url}/audience_preview`, payload, { signal });
  }

  analyticsContacts(id, { status, page } = {}) {
    return axios.get(`${this.url}/${id}/analytics/contacts`, {
      params: { status, page },
    });
  }
}

export default new CampaignsAPI();
