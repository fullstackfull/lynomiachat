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
  audiencePreview(audience, { signal } = {}) {
    return axios.post(`${this.url}/audience_preview`, { audience }, { signal });
  }

  analyticsContacts(id, { status, page } = {}) {
    return axios.get(`${this.url}/${id}/analytics/contacts`, {
      params: { status, page },
    });
  }
}

export default new CampaignsAPI();
