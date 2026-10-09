import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import TicketsRouteView from './pages/TicketsRouteView.vue';
import TicketsIndexPage from './pages/TicketsIndexPage.vue';
import TicketDetailPage from './pages/TicketDetailPage.vue';

// Lynomia Support cases (docs/p9/02-support-tickets.md).
//
// Every account member reaches this workspace, which is what the server already says: `Support::TicketPolicy`
// answers `index?` with true for everyone, and its Scope then narrows the list to the cases assigned to the
// reader, to one of their teams, or that they opened. `support_ticket_manage` widens that to the whole account,
// so gating the ROUTE on it would hide the workspace from exactly the agents it exists for.
const meta = {
  featureFlag: FEATURE_FLAGS.LYNOMIA_SUPPORT_TICKETS,
  permissions: ['administrator', 'agent', 'custom_role'],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/support/cases'),
      component: TicketsRouteView,
      children: [
        {
          path: '',
          name: 'support_tickets_index',
          meta,
          component: TicketsIndexPage,
        },
        {
          path: ':ticketId',
          name: 'support_tickets_show',
          meta,
          component: TicketDetailPage,
        },
      ],
    },
  ],
};
