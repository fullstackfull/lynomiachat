// The Platform Support Desk's client vocabulary (docs/platform-support/12-refresh-against-product-refinement.md §4).
//
// These mirror the server's frozen allow-lists. They are kept in sync by hand rather than fetched, because the
// category select and the status groupings have to render before any request is made; the server validates
// every value it is sent and is the authority if the two ever disagree.
//
// NOTE the difference from the TENANT desk's vocabulary (dashboard/constants/supportTickets.js): the fourth
// active status here is `waiting_on_lynomia`, not `waiting_on_internal`, and the eleven categories are a
// different set. The two desks are not the same product and must not share a constant.

export const PLATFORM_SUPPORT_STATUSES = [
  'open',
  'in_progress',
  'waiting_on_customer',
  'waiting_on_lynomia',
  'resolved',
  'closed',
];

export const PLATFORM_SUPPORT_OPEN_STATUSES = [
  'open',
  'in_progress',
  'waiting_on_customer',
  'waiting_on_lynomia',
];

export const PLATFORM_SUPPORT_CLOSED_STATUSES = ['resolved', 'closed'];

export const PLATFORM_SUPPORT_PRIORITIES = ['low', 'medium', 'high', 'urgent'];

export const PLATFORM_SUPPORT_DEFAULT_PRIORITY = 'medium';

export const PLATFORM_SUPPORT_CATEGORIES = [
  'billing',
  'account_access',
  'channel_connection',
  'whatsapp',
  'commerce',
  'campaigns',
  'automation',
  'performance',
  'data_export',
  'bug',
  'other',
];

export const PLATFORM_SUPPORT_DEFAULT_CATEGORY = 'other';

// The semantic each status carries, resolved to a colour by the design system's Label component. A status is
// given a meaning rather than a colour so a new one inherits the palette instead of picking from it.
export const PLATFORM_SUPPORT_STATUS_TONES = {
  open: 'info',
  in_progress: 'read',
  // The customer is the one holding this, so it reads as "your turn" rather than as a delay.
  waiting_on_customer: 'warning',
  waiting_on_lynomia: 'neutral',
  resolved: 'success',
  closed: 'neutral',
};

export const PLATFORM_SUPPORT_PRIORITY_TONES = {
  low: 'neutral',
  medium: 'info',
  high: 'warning',
  urgent: 'danger',
};

// The seven types CUSTOMER_VISIBLE_EVENT_TYPES allows (§1 M6). Anything else never reaches this client, and an
// unmapped type still renders with the fallback icon rather than as a blank row.
export const PLATFORM_SUPPORT_EVENT_ICONS = {
  created: 'i-lucide-circle-plus',
  status_changed: 'i-lucide-circle-dot',
  customer_replied: 'i-lucide-message-circle',
  operator_replied: 'i-lucide-message-circle-reply',
  resolved: 'i-lucide-circle-check',
  reopened: 'i-lucide-rotate-ccw',
  closed: 'i-lucide-archive',
};

export const PLATFORM_SUPPORT_EVENT_FALLBACK_ICON = 'i-lucide-dot';

// The two author roles the message payload uses. `lynomia` is always rendered as the literal "Lynomia
// Support": the API never sends an individual operator's name, and this client must never invent one.
export const PLATFORM_SUPPORT_AUTHOR_CUSTOMER = 'customer';
export const PLATFORM_SUPPORT_AUTHOR_LYNOMIA = 'lynomia';

export const PLATFORM_SUPPORT_SUBJECT_MAX_LENGTH = 255;
export const PLATFORM_SUPPORT_DESCRIPTION_MAX_LENGTH = 10000;
export const PLATFORM_SUPPORT_REPLY_MAX_LENGTH = 10000;

// Attachment limits, from docs/platform-support/03-authorization-security.md §7. Stated to the customer BEFORE
// the picker, never after a rejection; the server enforces them again and its refusal is shown as it came.
export const PLATFORM_SUPPORT_MAX_ATTACHMENTS = 5;
export const PLATFORM_SUPPORT_MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;
export const PLATFORM_SUPPORT_ACCEPTED_MIME_TYPES = [
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
  'application/pdf',
  'text/plain',
  'text/csv',
];

// The server's own page size for this list (§2). Pagination is only rendered past one page.
export const PLATFORM_SUPPORT_PAGE_SIZE = 25;
