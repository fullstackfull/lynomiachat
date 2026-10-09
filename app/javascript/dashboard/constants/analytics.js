// Lynomia Analytics client constants (docs/p8/02a-overview-conversation-analytics.md).
//
// These mirror Analytics::DateRange on the server. They are kept in sync by hand rather than fetched, because
// the group-by control has to render before any request is made; `GET /analytics` reports the same ceilings and
// is the authority if the two ever disagree.
export const ANALYTICS_GROUP_BY = {
  DAY: 'day',
  WEEK: 'week',
  MONTH: 'month',
};

export const ANALYTICS_MAX_BUCKETS = {
  [ANALYTICS_GROUP_BY.DAY]: 366,
  [ANALYTICS_GROUP_BY.WEEK]: 104,
  [ANALYTICS_GROUP_BY.MONTH]: 60,
};

export const ANALYTICS_DATE_FORMAT = 'yyyy-MM-dd';

export const DEFAULT_ANALYTICS_RANGE_DAYS = 30;

// `kind` on a KPI. A current-state reading is taken now, so it carries no period comparison and must not be
// drawn on a time axis.
export const ANALYTICS_KPI_KIND = {
  EVENT: 'event',
  CURRENT_STATE: 'current_state',
};

export const ANALYTICS_UNIT = {
  COUNT: 'count',
  SECONDS: 'seconds',
  PERCENT: 'percent',
};

// The dimensions each screen offers, mirroring the assemblers' BREAKDOWN_DIMENSIONS. `GET /analytics` reports
// the same lists under `breakdowns` and is the authority if the two ever disagree.
export const ANALYTICS_BREAKDOWN_DIMENSIONS = [
  'inbox',
  'channel',
  'team',
  'agent',
];

export const WHATSAPP_BREAKDOWN_DIMENSIONS = ['template', 'inbox', 'failure'];

export const CAMPAIGN_BREAKDOWN_DIMENSIONS = [
  'campaign',
  'audience',
  'failure',
  'skip_reason',
];

export const AUTOMATION_BREAKDOWN_DIMENSIONS = [
  'rule',
  'skip_reason',
  'status',
];

export const FLOW_BREAKDOWN_DIMENSIONS = [
  'bot',
  'status',
  'failure',
  'end_reason',
];

export const TICKET_BREAKDOWN_DIMENSIONS = [
  'priority',
  'category',
  'status',
  'team',
  'assignee',
];

export const COMMERCE_BREAKDOWN_DIMENSIONS = [
  'provider',
  'store',
  'currency',
  'action_type',
  'action_error',
];
