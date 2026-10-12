import { frontendURL } from 'dashboard/helper/URLHelper';

import PlatformSupportRouteView from './pages/PlatformSupportRouteView.vue';
import PlatformSupportIndexPage from './pages/PlatformSupportIndexPage.vue';
import PlatformSupportNewPage from './pages/PlatformSupportNewPage.vue';
import PlatformSupportDetailPage from './pages/PlatformSupportDetailPage.vue';

// The Platform Support Desk, customer side: the one place a Lynomia customer talks to Lynomia
// (docs/platform-support/04-customer-ux.md).
//
// UNDER `help/`, NOT `support/`. `accounts/:accountId/support/cases` is the TENANT ticketing module's own
// workspace -- the account's agents answering their own customers. These two must not read as siblings, and
// the route names are prefixed for the same reason (§9 of the implementation contract).
//
// EVERY MEMBER MAY OPEN A TICKET, so all three roles are on the route. What a member can then SEE is the
// policy's business and not the route's: an administrator sees every ticket of the account, an agent and a
// custom-role holder see only the ones they reported. Putting that narrowing in the route would hide the desk
// from exactly the people who need to reach it.
//
// NO FEATURE FLAG, deliberately and permanently. A customer who did not buy the tenant ticketing module must
// still be able to raise a ticket with Lynomia, and a billing-locked account reaches this desk too (§3). The
// desk is never gated and never sold.
const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/help/tickets'),
      component: PlatformSupportRouteView,
      children: [
        {
          path: '',
          name: 'platform_support_tickets_index',
          meta,
          component: PlatformSupportIndexPage,
        },
        // BEFORE `:ticketId`, or `new` is swallowed as a ticket id and the create form is unreachable.
        {
          path: 'new',
          name: 'platform_support_tickets_new',
          meta,
          component: PlatformSupportNewPage,
        },
        {
          path: ':ticketId',
          name: 'platform_support_tickets_show',
          meta,
          component: PlatformSupportDetailPage,
        },
      ],
    },
  ],
};
