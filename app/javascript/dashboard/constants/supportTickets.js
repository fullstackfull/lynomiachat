// Lynomia Support client constants (docs/p9/02-support-tickets.md).
//
// These mirror Support::Ticket's enums and Support::Tickets::Query's sort table. They are kept in sync by hand
// rather than fetched, because the filter bar and the view tabs have to render before any request is made; the
// server validates every value it is sent and is the authority if the two ever disagree.

export const TICKET_STATUSES = [
  'open',
  'in_progress',
  'waiting_on_customer',
  'waiting_on_internal',
  'resolved',
  'closed',
];

export const TICKET_ACTIVE_STATUSES = [
  'open',
  'in_progress',
  'waiting_on_customer',
  'waiting_on_internal',
];

export const TICKET_TERMINAL_STATUSES = ['resolved', 'closed'];

// The two pseudo-statuses the server resolves for us, so a client never has to spell out which concrete
// statuses count as active.
export const TICKET_STATUS_GROUPS = {
  ACTIVE: 'active',
  TERMINAL: 'terminal',
};

// Where a terminal case may go next, from Support::Tickets::StatusTransition. Any active status can become any
// other active or terminal one, so only the two exceptions are listed. Mirrored here so the status control
// offers what a case can actually reach: a usable control rather than a second guard -- the server still
// decides, and its refusal is shown exactly as it came.
export const TICKET_STATUS_TRANSITIONS = {
  resolved: ['closed', 'open'],
  closed: ['open'],
};

export const TICKET_PRIORITIES = ['low', 'medium', 'high', 'urgent'];

export const TICKET_CATEGORIES = [
  'technical',
  'billing',
  'account',
  'integration',
  'whatsapp',
  'commerce',
  'campaign',
  'automation',
  'operational',
  'other',
];

// The states `sla` can be filtered by. `none` is a case with no policy attached, which can never breach.
export const TICKET_SLA_STATES = [
  'overdue',
  'breached',
  'met_or_pending',
  'none',
];

// Exactly the keys Support::Tickets::Query::SORTS accepts, in the order the sort menu offers them. Anything
// else is a 422 naming the allowed set.
export const TICKET_SORTS = [
  'last_activity_at',
  'last_activity_at_asc',
  'created_at',
  'created_at_asc',
  'resolution_due_at',
  'priority',
];

export const TICKET_DEFAULT_SORT = 'last_activity_at';

// The server's own default and ceiling (Support::Tickets::Query).
export const TICKET_PAGE_SIZE = 25;

// The assignee filter's two literals, resolved server side so the client never needs its own user id nor a way
// to express a NULL.
export const TICKET_ASSIGNEE_ME = 'me';
export const TICKET_ASSIGNEE_UNASSIGNED = 'unassigned';

// The workspace's saved views. `countKey` names the figure in the list response's `meta.counts` that labels the
// tab, so a tab can never show a number the list below it disagrees with. `params` is merged UNDER the
// operator's own filters, so picking a status while on "My cases" narrows that view rather than being ignored.
export const TICKET_VIEWS = [
  { key: 'all', countKey: 'all', params: {} },
  {
    key: 'mine',
    countKey: 'mine',
    params: {
      assignee_id: TICKET_ASSIGNEE_ME,
      status: TICKET_STATUS_GROUPS.ACTIVE,
    },
  },
  {
    key: 'unassigned',
    countKey: 'unassigned',
    params: {
      assignee_id: TICKET_ASSIGNEE_UNASSIGNED,
      status: TICKET_STATUS_GROUPS.ACTIVE,
    },
  },
  { key: 'overdue', countKey: 'overdue', params: { sla: 'overdue' } },
  { key: 'resolved', countKey: 'resolved', params: { status: 'resolved' } },
  { key: 'closed', countKey: 'closed', params: { status: 'closed' } },
];

export const TICKET_DEFAULT_VIEW = 'all';

// 9999-12-31T23:59:59Z, the same ceiling the server applies to `since`/`until`.
export const TICKET_MAX_EPOCH = 253402300799;

export const TICKET_SEARCH_DEBOUNCE_DELAY = 500;

// The semantic each status carries, resolved to a colour by the design system's Label component. A status is
// given a meaning rather than a colour so a new one inherits the palette instead of picking from it.
export const TICKET_STATUS_TONES = {
  open: 'info',
  in_progress: 'read',
  // The one status that pauses the SLA clock, so it reads as parked rather than late.
  waiting_on_customer: 'neutral',
  // Waiting on ourselves is our own delay and the clock keeps running.
  waiting_on_internal: 'warning',
  resolved: 'success',
  closed: 'neutral',
};

export const TICKET_PRIORITY_TONES = {
  low: 'neutral',
  medium: 'info',
  high: 'warning',
  urgent: 'danger',
};

// How a case's SLA reads at a glance. `BREACHED` is a target the server has already recorded as missed;
// `OVERDUE` is a resolution target in the past on a case still active, which the sweep has not turned into a
// breach yet. `NONE` is a case with no policy attached, which can never breach and must not read as on time.
export const TICKET_SLA_STATE = {
  NONE: 'none',
  BREACHED: 'breached',
  OVERDUE: 'overdue',
  PAUSED: 'paused',
  MET: 'met',
  DUE: 'due',
};

export const TICKET_SLA_TONES = {
  [TICKET_SLA_STATE.NONE]: 'neutral',
  [TICKET_SLA_STATE.BREACHED]: 'danger',
  [TICKET_SLA_STATE.OVERDUE]: 'warning',
  [TICKET_SLA_STATE.PAUSED]: 'read',
  [TICKET_SLA_STATE.MET]: 'success',
  [TICKET_SLA_STATE.DUE]: 'neutral',
};

// The icon each history entry is drawn with. An event type with no entry here still renders, with the fallback
// dot, so a new server-side type is never a blank row.
export const TICKET_EVENT_ICONS = {
  created: 'i-lucide-circle-plus',
  note: 'i-lucide-sticky-note',
  status_changed: 'i-lucide-circle-dot',
  priority_changed: 'i-lucide-flag',
  assigned: 'i-lucide-user-round',
  team_changed: 'i-lucide-users',
  category_changed: 'i-lucide-tag',
  conversation_linked: 'i-lucide-link',
  conversation_unlinked: 'i-lucide-unlink',
  sla_applied: 'i-lucide-timer',
  sla_first_response_met: 'i-lucide-timer-reset',
  sla_first_response_breached: 'i-lucide-timer-off',
  sla_resolution_breached: 'i-lucide-circle-alert',
  resolved: 'i-lucide-circle-check',
  reopened: 'i-lucide-rotate-ccw',
  closed: 'i-lucide-archive',
};

export const TICKET_EVENT_FALLBACK_ICON = 'i-lucide-dot';

export const TICKET_NOTE_EVENT_TYPE = 'note';

// A note is an internal remark, not a message to the customer, so it is bounded well below the ticket
// description's 10,000 and the box says how much is left.
export const TICKET_NOTE_MAX_LENGTH = 2000;

export const TICKET_TITLE_MAX_LENGTH = 255;

export const TICKET_DESCRIPTION_MAX_LENGTH = 10000;

// SLA thresholds are seconds on the wire. The form collects minutes, which is what DurationInput speaks.
export const SECONDS_PER_MINUTE = 60;
