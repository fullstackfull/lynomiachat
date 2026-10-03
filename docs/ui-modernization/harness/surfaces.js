// The surfaces the gallery can render. Each entry lazily imports a REAL page or component, so only that surface's
// module graph loads — eager imports of the whole dashboard deadlock on Chatwoot's own circular imports, and the
// bundle is an order of magnitude smaller this way.
//
// `interactions` are selectors clicked before capture, so controls behind a menu or dialog land in the inventory
// too: a feature that exists only inside an unopened menu still has to survive a redesign.
export const SURFACES = {
  sidebar: {
    title: 'Main sidebar',
    load: () => import('dashboard/components-next/sidebar/Sidebar.vue'),
    frame: 'sidebar',
  },
  'flows-list': {
    title: 'Settings · Flow Builder list',
    load: () => import('dashboard/routes/dashboard/settings/flows/Index.vue'),
    route: 'settings_flows_index',
    frame: 'settings',
  },
  'flows-list-empty': {
    title: 'Settings · Flow Builder list (empty)',
    load: () => import('dashboard/routes/dashboard/settings/flows/Index.vue'),
    route: 'settings_flows_index',
    frame: 'settings',
    state: 'empty',
  },
  'automation-list': {
    title: 'Settings · Automation list',
    load: () => import('dashboard/routes/dashboard/settings/automation/Index.vue'),
    route: 'automation_list',
    frame: 'settings',
  },
  'automation-list-empty': {
    title: 'Settings · Automation list (empty)',
    load: () => import('dashboard/routes/dashboard/settings/automation/Index.vue'),
    route: 'automation_list',
    frame: 'settings',
    state: 'empty',
  },
  'commerce-settings': {
    title: 'Settings · Commerce stores',
    load: () => import('dashboard/routes/dashboard/settings/commerce/Index.vue'),
    route: 'settings_commerce_index',
    frame: 'settings',
  },
  'labels-list': {
    title: 'Settings · Labels',
    load: () => import('dashboard/routes/dashboard/settings/labels/Index.vue'),
    route: 'labels_list',
    frame: 'settings',
  },
  'teams-list': {
    title: 'Settings · Teams',
    load: () => import('dashboard/routes/dashboard/settings/teams/Index.vue'),
    route: 'settings_teams_list',
    frame: 'settings',
  },
  'agents-list': {
    title: 'Settings · Agents',
    load: () => import('dashboard/routes/dashboard/settings/agents/Index.vue'),
    route: 'agent_list',
    frame: 'settings',
  },
  'contacts-header': {
    title: 'Contacts · header and audience actions',
    load: () => import('dashboard/components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue'),
    route: 'contacts_dashboard_segments_index',
    frame: 'plain',
    props: {
      headerTitle: 'VIP buyers',
      segmentsId: 7,
      activeSegment: {
        id: 7,
        name: 'VIP buyers',
        shared: true,
        query: { payload: [] },
        active_automation_rules_count: 2,
        campaigns_count: 1,
      },
    },
    interactions: ['[data-test-id="contact-more-actions"]'],
  },
  'canned-list': {
    title: 'Settings · Canned responses',
    load: () => import('dashboard/routes/dashboard/settings/canned/Index.vue'),
    route: 'canned_list',
    frame: 'settings',
  },
  'macros-list': {
    title: 'Settings · Macros',
    load: () => import('dashboard/routes/dashboard/settings/macros/Index.vue'),
    route: 'macros_wrapper',
    frame: 'settings',
  },
  'attributes-list': {
    title: 'Settings · Custom attributes',
    load: () => import('dashboard/routes/dashboard/settings/attributes/Index.vue'),
    route: 'attributes_list',
    frame: 'settings',
  },
  'sla-list': {
    title: 'Settings · SLA policies',
    load: () => import('dashboard/routes/dashboard/settings/sla/Index.vue'),
    route: 'sla_list',
    frame: 'settings',
  },
  'custom-roles-list': {
    title: 'Settings · Custom roles',
    load: () => import('dashboard/routes/dashboard/settings/customRoles/Index.vue'),
    route: 'custom_roles_list',
    frame: 'settings',
  },
  'templates-list': {
    title: 'Settings · WhatsApp templates',
    load: () => import('dashboard/routes/dashboard/settings/templates/Index.vue'),
    route: 'settings_templates',
    frame: 'settings',
  },
  'inboxes-list': {
    title: 'Settings · Inboxes',
    load: () => import('dashboard/routes/dashboard/settings/inbox/Index.vue'),
    route: 'settings_inbox_list',
    frame: 'settings',
  },
  'campaigns-whatsapp': {
    title: 'Campaigns · WhatsApp',
    load: () => import('dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignsPage.vue'),
    route: 'campaigns_whatsapp_index',
    frame: 'plain',
  },
  'automation-recipes-dialog': {
    title: 'Settings · Automation · recipe dialog',
    load: () => import('dashboard/routes/dashboard/settings/automation/Index.vue'),
    route: 'automation_list',
    frame: 'settings',
    interactions: ['[data-test-id="automation-recipes-button"]'],
  },
  'flows-templates-dialog': {
    title: 'Settings · Flow Builder · template dialog',
    load: () => import('dashboard/routes/dashboard/settings/flows/Index.vue'),
    route: 'settings_flows_index',
    frame: 'settings',
    interactions: ['[data-test-id="flow-templates-button"]'],
  },
  'labels-add-modal': {
    title: 'Settings · Labels · add (legacy modal)',
    load: () => import('dashboard/routes/dashboard/settings/labels/Index.vue'),
    route: 'labels_list',
    frame: 'settings',
    interactions: ['text:Add label'],
  },
  'labels-list-empty': {
    title: 'Settings · Labels (empty)',
    load: () => import('dashboard/routes/dashboard/settings/labels/Index.vue'),
    route: 'labels_list',
    frame: 'settings',
    state: 'empty',
  },
  'teams-list-empty': {
    title: 'Settings · Teams (empty)',
    load: () => import('dashboard/routes/dashboard/settings/teams/Index.vue'),
    route: 'settings_teams_list',
    frame: 'settings',
    state: 'empty',
  },
};
