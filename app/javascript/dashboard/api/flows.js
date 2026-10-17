/* global axios */

import ApiClient from './ApiClient';

// Lynomia Flow Builder (docs/flow-builder/02-architecture.md): the account's flow bots and their versioned graphs.
// A flow is connected to an inbox with the inboxes API (setAgentBot), as any bot is.
class FlowsAPI extends ApiClient {
  constructor() {
    super('flows', { accountScoped: true });
  }

  // `lockVersion` is the draft's lock_version as this editor loaded it, and the server REQUIRES it:
  // a save against a draft somebody else has since changed answers 409 with their graph rather than
  // overwriting their work. Callers must pass the value from the flow they are editing.
  saveDraft(id, graph, lockVersion) {
    return axios.put(`${this.url}/${id}/draft`, {
      graph,
      lock_version: lockVersion,
    });
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
