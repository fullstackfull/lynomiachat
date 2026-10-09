import {
  TICKET_ACTIVE_STATUSES,
  TICKET_ASSIGNEE_ME,
  TICKET_ASSIGNEE_UNASSIGNED,
  TICKET_CATEGORIES,
  TICKET_DEFAULT_VIEW,
  TICKET_MAX_EPOCH,
  TICKET_PAGE_SIZE,
  TICKET_PRIORITIES,
  TICKET_SLA_STATE,
  TICKET_SLA_STATES,
  TICKET_SORTS,
  TICKET_STATUSES,
  TICKET_STATUS_GROUPS,
  TICKET_STATUS_TRANSITIONS,
  TICKET_TERMINAL_STATUSES,
  TICKET_VIEWS,
} from 'dashboard/constants/supportTickets';

// Pure query mapping for the support workspace (docs/p9/02-support-tickets.md).
//
// The URL is the single source of truth for the list, exactly as the audit log reader does it: one function
// reads a route query into filters, another writes filters back into a route query. Keeping both pure is what
// lets the list, the view tabs, the filter bar and the pagination footer all drive the same navigation without
// any of them holding a second copy of the state.

const STATUS_VALUES = [
  ...TICKET_STATUSES,
  ...Object.values(TICKET_STATUS_GROUPS),
];
const VIEW_KEYS = TICKET_VIEWS.map(view => view.key);
const ASSIGNEE_LITERALS = [TICKET_ASSIGNEE_ME, TICKET_ASSIGNEE_UNASSIGNED];

const positiveInteger = value => {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : null;
};

const epoch = value => {
  const number = positiveInteger(value);
  return number !== null && number <= TICKET_MAX_EPOCH ? number : null;
};

/**
 * Reads a route query into the list's filters, dropping anything the server would reject.
 *
 * A value that is dropped here would have come back as a 422 naming the allowed set, which is the right answer
 * for a hand-typed request but the wrong one for a stale bookmark: the page should still open.
 *
 * @param {object} query - `route.query`.
 * @returns {object} The filters, always carrying a `view` and a `page`.
 */
export const ticketFiltersFromQuery = (query = {}) => {
  const filters = {
    view: VIEW_KEYS.includes(query.view) ? query.view : TICKET_DEFAULT_VIEW,
    page: positiveInteger(query.page) || 1,
  };

  if (query.q) filters.q = String(query.q);
  if (STATUS_VALUES.includes(query.status)) filters.status = query.status;
  if (TICKET_PRIORITIES.includes(query.priority)) {
    filters.priority = query.priority;
  }
  if (TICKET_CATEGORIES.includes(query.category)) {
    filters.category = query.category;
  }
  if (TICKET_SLA_STATES.includes(query.sla)) filters.sla = query.sla;
  if (TICKET_SORTS.includes(query.sort)) filters.sort = query.sort;

  if (ASSIGNEE_LITERALS.includes(query.assignee_id)) {
    filters.assignee_id = query.assignee_id;
  } else if (positiveInteger(query.assignee_id)) {
    filters.assignee_id = positiveInteger(query.assignee_id);
  }

  // The link filters. Read from the query like every other one, so the Cases tab on a contact and the cases
  // panel on a conversation can hand the workspace a link that opens exactly what they were showing.
  ['team_id', 'contact_id', 'inbox_id', 'conversation_id'].forEach(key => {
    const id = positiveInteger(query[key]);
    if (id) filters[key] = id;
  });

  // Both ends or neither: half a window is a question nobody asked.
  const since = epoch(query.since);
  const until = epoch(query.until);
  if (since && until) {
    filters.since = since;
    filters.until = until;
  }

  return filters;
};

/**
 * Drops the empty entries a route query must not carry, so `?status=` never reaches the address bar.
 *
 * @param {object} query - The merged query to write.
 * @returns {object} The same entries without the empty ones.
 */
export const buildTicketRouteQuery = (query = {}) =>
  Object.fromEntries(
    Object.entries(query).filter(
      ([, value]) => value !== undefined && value !== '' && value !== null
    )
  );

/**
 * Turns filters into the request the list endpoint takes.
 *
 * The selected view's parameters go UNDER the operator's own filters: picking a status while on "My cases"
 * narrows that view instead of being silently ignored, and nothing the operator chose is ever dropped.
 *
 * @param {object} filters - The output of `ticketFiltersFromQuery`.
 * @returns {object} Query parameters for `GET support/tickets`.
 */
export const ticketRequestParams = (filters = {}) => {
  const view = TICKET_VIEWS.find(entry => entry.key === filters.view);
  const explicit = Object.fromEntries(
    Object.entries(filters).filter(([key]) => key !== 'view' && key !== 'page')
  );

  return {
    ...(view?.params || {}),
    ...explicit,
    page: filters.page,
    per_page: TICKET_PAGE_SIZE,
  };
};

/**
 * Whether the operator has narrowed the list beyond the plain view, which is what the "clear" action acts on.
 *
 * @param {object} filters - The output of `ticketFiltersFromQuery`.
 * @returns {boolean} True when any filter beyond the view and the page is set.
 */
export const hasActiveTicketFilters = (filters = {}) =>
  Object.keys(filters).some(key => key !== 'view' && key !== 'page');

/**
 * How a case's SLA reads at a glance.
 *
 * `breached` comes from the server, which has already recorded the miss. `overdue` is the gap between a
 * resolution target falling into the past and the sweep recording it, and only applies while the case is still
 * active. A case with no policy is `none`, never "on time": every SLA figure in this product begins when a
 * policy is attached, so silence is not evidence of a target met.
 *
 * @param {object} ticket - One ticket as the API returns it.
 * @param {number} nowInSeconds - The current time, in epoch seconds.
 * @returns {string} One of `TICKET_SLA_STATE`.
 */
export const ticketSlaState = (ticket, nowInSeconds) => {
  const sla = ticket?.sla;
  if (!sla?.applied) return TICKET_SLA_STATE.NONE;
  if (sla.breached) return TICKET_SLA_STATE.BREACHED;
  if (TICKET_TERMINAL_STATUSES.includes(ticket.status)) {
    return TICKET_SLA_STATE.MET;
  }
  if (sla.paused) return TICKET_SLA_STATE.PAUSED;
  if (sla.resolution_due_at && sla.resolution_due_at < nowInSeconds) {
    return TICKET_SLA_STATE.OVERDUE;
  }
  return TICKET_SLA_STATE.DUE;
};

/**
 * Whether a case can still be worked, which is what decides if the detail view offers a note box.
 *
 * @param {object} ticket - One ticket as the API returns it.
 * @returns {boolean} True while the case is in one of the four active statuses.
 */
export const isTicketActive = ticket =>
  TICKET_ACTIVE_STATUSES.includes(ticket?.status);

/**
 * The statuses a case can move to, including the one it is already in.
 *
 * Offering only reachable states is what keeps the control usable; the server's transition table remains the
 * authority, and a refusal from it is shown with the message it came with.
 *
 * @param {string} status - The case's current status.
 * @returns {Array<string>} The reachable statuses, in the product's own order.
 */
export const allowedTicketStatuses = status => {
  const reachable = new Set([
    status,
    ...(TICKET_STATUS_TRANSITIONS[status] || [
      ...TICKET_ACTIVE_STATUSES,
      ...TICKET_TERMINAL_STATUSES,
    ]),
  ]);
  return TICKET_STATUSES.filter(value => reachable.has(value));
};
