// Contact activity timeline client constants (docs/p8/03-contact-activity-timeline.md).

// `ALL` is the absence of a filter rather than a category the server knows: omitting `categories` asks for
// every one.
export const CONTACT_ACTIVITY_CATEGORIES = {
  ALL: 'all',
  MESSAGES: 'messages',
  CONVERSATIONS: 'conversations',
  CAMPAIGNS: 'campaigns',
  AUTOMATIONS: 'automations',
  COMMERCE: 'commerce',
  TICKETS: 'tickets',
};

export const CONTACT_ACTIVITY_FILTERS = Object.values(
  CONTACT_ACTIVITY_CATEGORIES
);

// Well under the server's maximum of 100, because this list lives in a sidebar and is read by scrolling.
export const CONTACT_ACTIVITY_PAGE_SIZE = 25;

// The icon each entry kind is drawn with. A kind with no entry here still renders, with the fallback dot, so a
// new server-side kind is never a blank row.
export const CONTACT_ACTIVITY_ICONS = {
  message_incoming: 'i-lucide-message-circle',
  message_outgoing: 'i-lucide-send',
  message_system_template: 'i-lucide-file-text',
  private_note: 'i-lucide-lock',
  conversation_created: 'i-lucide-message-square-plus',
  conversation_status_changed: 'i-lucide-circle-dot',
  conversation_activity: 'i-lucide-activity',
  conversation_reopened: 'i-lucide-rotate-ccw',
  conversation_resolved: 'i-lucide-circle-check',
  first_response: 'i-lucide-timer',
  bot_handoff: 'i-lucide-user-round',
  bot_resolved: 'i-lucide-bot',
  csat_response: 'i-lucide-star',
  campaign_queued: 'i-lucide-megaphone',
  campaign_skipped: 'i-lucide-circle-slash',
  campaign_sent: 'i-lucide-megaphone',
  campaign_delivered: 'i-lucide-check-check',
  campaign_read: 'i-lucide-eye',
  campaign_failed: 'i-lucide-circle-alert',
  automation_executed: 'i-lucide-zap',
  automation_skipped: 'i-lucide-zap-off',
  flow_completed: 'i-lucide-circle-check',
  flow_failed: 'i-lucide-circle-alert',
  flow_cancelled: 'i-lucide-circle-slash',
  flow_handed_off: 'i-lucide-user-round',
  cart_abandoned: 'i-lucide-shopping-cart',
  cart_completed: 'i-lucide-package-check',
  commerce_action_pending: 'i-lucide-hourglass',
  commerce_action_running: 'i-lucide-hourglass',
  commerce_action_succeeded: 'i-lucide-circle-check',
  commerce_action_failed: 'i-lucide-circle-alert',
  commerce_action_unknown: 'i-lucide-circle-help',
  commerce_customer_linked: 'i-lucide-link',
  // Support cases (P9). The server emits one entry per history event, with the event type as the kind's
  // suffix, so every type Support::TicketEvent can record needs an icon here.
  ticket_created: 'i-lucide-circle-plus',
  ticket_note: 'i-lucide-sticky-note',
  ticket_status_changed: 'i-lucide-circle-dot',
  ticket_priority_changed: 'i-lucide-flag',
  ticket_assigned: 'i-lucide-user-round',
  ticket_team_changed: 'i-lucide-users',
  ticket_category_changed: 'i-lucide-tag',
  ticket_conversation_linked: 'i-lucide-link',
  ticket_conversation_unlinked: 'i-lucide-unlink',
  ticket_sla_applied: 'i-lucide-timer',
  ticket_sla_first_response_met: 'i-lucide-timer-reset',
  ticket_sla_first_response_breached: 'i-lucide-timer-off',
  ticket_sla_resolution_breached: 'i-lucide-circle-alert',
  ticket_resolved: 'i-lucide-circle-check',
  ticket_reopened: 'i-lucide-rotate-ccw',
  ticket_closed: 'i-lucide-archive',
};

export const CONTACT_ACTIVITY_FALLBACK_ICON = 'i-lucide-dot';
