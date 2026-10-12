/* global axios */
import ApiClient from './ApiClient';

// Lynomia Support cases (docs/p9/02-support-tickets.md).
//
// Every timestamp this endpoint family exchanges is epoch SECONDS, and `since`/`until` are sent the same way --
// unlike Analytics, which takes calendar dates because the server cuts buckets in the account's own timezone.
// A case's clock is an instant, not a calendar day, so the two contracts differ on purpose.
//
// `signal` is passed through on every call so a screen can discard a superseded request while the operator is
// still typing in the search box or clicking through filters (dashboard/composables/useSupportTickets.js).
class SupportTicketsAPI extends ApiClient {
  constructor() {
    super('support/tickets', { accountScoped: true });
  }

  getTickets(params = {}, { signal } = {}) {
    return axios.get(this.url, { params, signal });
  }

  // `id` accepts a reference as well as a numeric id, because an operator pastes `TCK-000123` from an email.
  getTicket(id, { signal } = {}) {
    return axios.get(`${this.url}/${id}`, { signal });
  }

  // `status` is not accepted here: a new case always opens.
  createTicket(ticket, { signal } = {}) {
    return axios.post(this.url, { ticket }, { signal });
  }

  updateTicket(id, ticket, { signal } = {}) {
    return axios.patch(`${this.url}/${id}`, { ticket }, { signal });
  }

  getEvents(id, params = {}, { signal } = {}) {
    return axios.get(`${this.url}/${id}/events`, { params, signal });
  }

  // Only an internal note can be created through the API; every other event type is written by the service
  // that performed the change.
  createNote(id, body, { signal } = {}) {
    return axios.post(
      `${this.url}/${id}/events`,
      { event: { body } },
      { signal }
    );
  }

  get slaPoliciesUrl() {
    return `${this.baseUrl()}/support/sla_policies`;
  }

  getSlaPolicies({ signal } = {}) {
    return axios.get(this.slaPoliciesUrl, { signal });
  }

  // Thresholds are SECONDS on the wire; the settings form collects minutes or hours and converts.
  createSlaPolicy(slaPolicy, { signal } = {}) {
    return axios.post(
      this.slaPoliciesUrl,
      { sla_policy: slaPolicy },
      { signal }
    );
  }

  updateSlaPolicy(id, slaPolicy, { signal } = {}) {
    return axios.patch(
      `${this.slaPoliciesUrl}/${id}`,
      { sla_policy: slaPolicy },
      { signal }
    );
  }

  deleteSlaPolicy(id, { signal } = {}) {
    return axios.delete(`${this.slaPoliciesUrl}/${id}`, { signal });
  }
}

export default new SupportTicketsAPI();
