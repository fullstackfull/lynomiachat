/* global axios */

import ApiClient from './ApiClient';

// Lynomia Flow Builder (docs/flow-builder/02-architecture.md): the account's flow bots and their versioned graphs.
// A flow is connected to an inbox with the inboxes API (setAgentBot), as any bot is.
class FlowsAPI extends ApiClient {
  constructor() {
    super('flows', { accountScoped: true });
  }

  saveDraft(id, graph) {
    return axios.put(`${this.url}/${id}/draft`, { graph });
  }

  publish(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  disable(id) {
    return axios.post(`${this.url}/${id}/disable`);
  }

  sessions(id, status) {
    return axios.get(`${this.url}/${id}/sessions`, {
      params: status ? { status } : {},
    });
  }

  // Test Mode: the draft run on the real runtime and rolled back; `inputs` is the tester's whole input list.
  simulate(id, inputs) {
    return axios.post(`${this.url}/${id}/simulate`, { inputs });
  }
}

export default new FlowsAPI();
