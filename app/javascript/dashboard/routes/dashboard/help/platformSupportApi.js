/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

/**
 * The Platform Support Desk's tenant endpoints, exactly as §2 of
 * docs/platform-support/12-refresh-against-product-refinement.md freezes them. Nothing here invents a path, a
 * verb or a key: if a screen needs something this file does not expose, the contract is what changes.
 *
 * `/api/v1/accounts/:account_id/platform_support/tickets[...]`, plus the one attachment route.
 *
 * TWO THINGS DELIBERATELY ABSENT, and they are absent here so they cannot be added by accident elsewhere:
 *
 *   - there is no `destroy`. A ticket is closed, never deleted.
 *   - there is no internal-notes method, not even a filtered one. Internal notes have no tenant surface at
 *     all; nothing in this bundle may reference them.
 *
 * Every timestamp this family exchanges is a unix-second integer. `signal` is passed through on every call so
 * a screen can discard a superseded request (dashboard/composables/useAbortableRequest.js).
 */
class PlatformSupportAPI extends ApiClient {
  constructor() {
    super('platform_support/tickets', { accountScoped: true });
  }

  getTickets(params = {}, { signal } = {}) {
    return axios.get(this.url, { params, signal });
  }

  // `id` accepts a `LYN-` reference as well as a numeric id, because a customer pastes the reference out of
  // the email they were sent.
  getTicket(id, { signal } = {}) {
    return axios.get(`${this.url}/${id}`, { signal });
  }

  // `status` is not accepted here: a new ticket always opens.
  createTicket(ticket, { signal } = {}) {
    return axios.post(this.url, { ticket }, { signal });
  }

  // Accepts `priority`, and `status: 'closed'` only on a resolved ticket. Everything else is refused server
  // side, which is why this method does not filter: a client-side filter would hide the refusal.
  updateTicket(id, ticket, { signal } = {}) {
    return axios.patch(`${this.url}/${id}`, { ticket }, { signal });
  }

  getMessages(id, params = {}, { signal } = {}) {
    return axios.get(`${this.url}/${id}/messages`, { params, signal });
  }

  // 422 when the ticket is closed. On a `resolved` ticket this succeeds AND reopens it, so the caller refetches
  // the ticket rather than assuming the status it had.
  createMessage(id, message, { signal } = {}) {
    return axios.post(`${this.url}/${id}/messages`, { message }, { signal });
  }

  getEvents(id, { signal } = {}) {
    return axios.get(`${this.url}/${id}/events`, { signal });
  }

  markViewed(id, { signal } = {}) {
    return axios.post(`${this.url}/${id}/mark_viewed`, {}, { signal });
  }

  /**
   * The address of one attachment's authorized download.
   *
   * The ONLY way a blob on this surface is ever reached. The payload carries no `url`, because blob URLs do
   * not expire in this installation and a leaked signed id would be a permanent one; the server authorizes the
   * attachment's PARENT record through the policy scope and then streams
   * (docs/platform-support/12-refresh-against-product-refinement.md §3). An internal note's attachment 404s
   * here as a consequence of that lookup, not as a case anybody has to remember.
   * @param {number|string} attachmentId - the attachment id from a message payload
   * @returns {string} the download path
   */
  attachmentUrl(attachmentId) {
    return `${this.baseUrl()}/platform_support/attachments/${attachmentId}`;
  }

  /**
   * Uploads one file and returns the signed blob id to send as an `attachment_ids` member.
   *
   * Through the installation's existing scoped, authenticated upload endpoint, which is what
   * docs/platform-support/03-authorization-security.md §7 requires ("Direct upload: through the existing
   * scoped, authenticated upload endpoints"): the bare Rails direct-upload route is blocked here, and this
   * module adds no second upload path of its own. Only `blob_id` is read -- the `file_url` that endpoint also
   * returns is a permanent bearer token for the blob and must never be stored or rendered.
   * @param {File} file - the file the customer picked
   * @param {{signal?: AbortSignal}} options - request options
   * @returns {Promise<string>} the signed blob id
   */
  async uploadAttachment(file, { signal } = {}) {
    const form = new FormData();
    form.append('attachment', file);

    const response = await axios.post(`${this.baseUrl()}/upload`, form, {
      signal,
    });

    return response.data.blob_id;
  }
}

export default new PlatformSupportAPI();
