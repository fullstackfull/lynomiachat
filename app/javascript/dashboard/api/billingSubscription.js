/* global axios */
import ApiClient from './ApiClient';

// Custom billing API: /api/v1/accounts/:accountId/billing
class BillingSubscriptionAPI extends ApiClient {
  constructor() {
    super('billing', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  checkout(planId) {
    return axios.post(`${this.url}/checkout`, { plan_id: planId });
  }

  portal() {
    return axios.post(`${this.url}/portal`);
  }

  changePlanPreview(planId) {
    return axios.post(`${this.url}/change_plan_preview`, { plan_id: planId });
  }

  changePlan(planId, prorationDate) {
    return axios.post(`${this.url}/change_plan`, {
      plan_id: planId,
      proration_date: prorationDate,
    });
  }
}

export default new BillingSubscriptionAPI();
