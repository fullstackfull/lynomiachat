/* global axios */

import ApiClient from './ApiClient';

// The one-time code an account administrator mints so an external platform may link this workspace
// (Integrations::AccountLinkCode). The code is shown once and only its HMAC is kept server side; nothing here
// holds a credential, and the platform redeems the code over its own server-to-server token, never the browser.
class AccountLinkAPI extends ApiClient {
  constructor() {
    super('integrations/account_link_code', { accountScoped: true });
  }

  createCode() {
    return axios.post(this.url);
  }

  getStatus() {
    return axios.get(this.url);
  }
}

export default new AccountLinkAPI();
