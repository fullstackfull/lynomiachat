/* global axios */

import ApiClient from './ApiClient';

// What this workspace has given away, and taking it back.
//
// Until this existed a grant could only be withdrawn by the integration holding it, which is the wrong party:
// the merchant consented and the merchant's workspace is what is at stake. `get` also carries the list of
// integrations a link code may be minted for, because the two questions are asked on the same page and a
// second round trip to answer the easier one is a second thing that can be out of date.
//
// No credential crosses this surface. A PlatformApp owns an access token; only its id and name are rendered.
class AccountGrantsAPI extends ApiClient {
  constructor() {
    super('integrations/grants', { accountScoped: true });
  }

  revoke(platformAppId) {
    return axios.delete(`${this.url}/${platformAppId}`);
  }
}

export default new AccountGrantsAPI();
