/* global axios */

import ApiClient from './ApiClient';

// Lynomia Commerce: store connections (administrators) and the conversation Commerce panel.
class CommerceAPI extends ApiClient {
  constructor() {
    super('commerce/stores', { accountScoped: true });
  }

  sallaConnectionUrl() {
    return `${this.baseUrl()}/commerce/salla_connection`;
  }

  // A one-time code the merchant enters in the Lynomia app's settings in Salla, and the Salla install link.
  createSallaConnection() {
    return axios.post(this.sallaConnectionUrl());
  }

  getSallaConnection() {
    return axios.get(this.sallaConnectionUrl());
  }

  // The Zid authorization link for "Connect with Zid" (the browser is sent there; Zid redirects back to Lynomia).
  createZidConnection() {
    return axios.post(`${this.baseUrl()}/commerce/zid_connection`);
  }

  // The shop's authorization link for "Connect with Shopify" (the browser is sent there; Shopify redirects back to
  // Lynomia). `shop` is the store's myshopify.com domain.
  createShopifyConnection(shop) {
    return axios.post(`${this.baseUrl()}/commerce/shopify_connection`, {
      shop,
    });
  }

  conversationStoresUrl(conversationId) {
    return `${this.baseUrl()}/conversations/${conversationId}/commerce/stores`;
  }

  getConversationStores(conversationId, { signal } = {}) {
    return axios.get(this.conversationStoresUrl(conversationId), { signal });
  }

  // Customer 360: every connected store's view of the conversation's contact, aggregated.
  getOverview(conversationId, { signal } = {}) {
    return axios.get(
      `${this.baseUrl()}/conversations/${conversationId}/commerce/overview`,
      { signal }
    );
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
