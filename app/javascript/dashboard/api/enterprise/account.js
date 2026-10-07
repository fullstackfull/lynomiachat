/* global axios */
import ApiClient from '../ApiClient';

// Captain's usage quota, the one thing left that reads Chatwoot's Enterprise account endpoints. Only ever
// called behind `isEnterprise` (dashboard/composables/useCaptain.js), so it is inert on a Lynomia install.
// The cloud billing methods -- checkout, subscription, billing_summary, currency selection, top-ups -- and
// account self-deletion are gone: Lynomia bills through its own API.
class EnterpriseAccountAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true, enterprise: true });
  }

  getLimits() {
    return axios.get(`${this.url}limits`);
  }
}

export default new EnterpriseAccountAPI();
