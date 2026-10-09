/* global axios */
import ApiClient from './ApiClient';

// Lynomia Analytics (docs/p8/02-analytics.md).
//
// Every endpoint takes calendar dates (`since`, `until` as YYYY-MM-DD) rather than instants, because the server
// cuts buckets in the account's own reporting timezone. Sending epoch seconds computed from the browser clock
// would make the same requested period produce different totals for two viewers, which is exactly what the
// account-timezone contract exists to prevent.
//
// `signal` is passed through so a screen can discard a superseded request while the operator is still dragging
// through a date picker (dashboard/composables/useAnalyticsQuery.js).
class AnalyticsAPI extends ApiClient {
  constructor() {
    super('analytics', { accountScoped: true });
  }

  // The account's analytics contract: timezone, resolved range, bucket ceilings, families and their filters.
  getMeta(params = {}, { signal } = {}) {
    return axios.get(this.url, { params, signal });
  }

  getOverview(params = {}, { signal } = {}) {
    return axios.get(`${this.url}/overview`, { params, signal });
  }
}

export default new AnalyticsAPI();
