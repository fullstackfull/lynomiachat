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
  // Lynomia). `shop` is the store's myshopify.com domain; `orderActions` also asks Shopify for write access to orders.
  createShopifyConnection(shop, { orderActions = false } = {}) {
    return axios.post(`${this.baseUrl()}/commerce/shopify_connection`, {
      shop,
      ...(orderActions ? { order_actions: true } : {}),
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

  // Reads the current view again from the stores (rate-limited server-side). Without a store: the Customer 360 overview.
  refresh(conversationId, storeId = null) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/commerce/refresh`,
      null,
      { params: storeId ? { store_id: storeId } : {} }
    );
  }

  // Orders with this number (digits, an optional leading #) in one store, or in every store without one.
  searchOrders(conversationId, number, storeId = null) {
    return axios.get(
      `${this.baseUrl()}/conversations/${conversationId}/commerce/orders`,
      { params: storeId ? { number, store_id: storeId } : { number } }
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

  orderActionsUrl(conversationId, storeId, orderId) {
    return `${this.conversationStoresUrl(conversationId)}/${storeId}/orders/${orderId}/actions`;
  }

  // What can be done to the order now: read from the store, with Lynomia's rules and this agent's permissions applied.
  getOrderActions(conversationId, storeId, orderId) {
    return axios.get(this.orderActionsUrl(conversationId, storeId, orderId));
  }

  // One confirmed action: { action_type, version, idempotency_key, params }. Answered with the queued run.
  requestOrderAction(conversationId, storeId, orderId, payload) {
    return axios.post(
      this.orderActionsUrl(conversationId, storeId, orderId),
      payload
    );
  }

  getActionRun(conversationId, runId) {
    return axios.get(
      `${this.baseUrl()}/conversations/${conversationId}/commerce/action_runs/${runId}`
    );
  }
}

export default new CommerceAPI();
