/* global axios */

import ApiClient from './ApiClient';

// Lynomia Commerce: store connections (administrators) and the conversation Commerce panel.
class CommerceAPI extends ApiClient {
  constructor() {
    super('commerce/stores', { accountScoped: true });
  }

  conversationStoresUrl(conversationId) {
    return `${this.baseUrl()}/conversations/${conversationId}/commerce/stores`;
  }

  getConversationStores(conversationId, { signal } = {}) {
    return axios.get(this.conversationStoresUrl(conversationId), { signal });
  }

  getPanel(conversationId, storeId, { signal } = {}) {
    return axios.get(
      `${this.conversationStoresUrl(conversationId)}/${storeId}`,
      { signal }
    );
  }

  searchCustomers(conversationId, storeId, query) {
    return axios.get(
      `${this.conversationStoresUrl(conversationId)}/${storeId}/customers`,
      { params: { query } }
    );
  }

  linkCustomer(conversationId, storeId, token) {
    return axios.post(
      `${this.conversationStoresUrl(conversationId)}/${storeId}/link`,
      { token }
    );
  }

  unlinkCustomer(conversationId, storeId) {
    return axios.delete(
      `${this.conversationStoresUrl(conversationId)}/${storeId}/link`
    );
  }
}

export default new CommerceAPI();
