import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL } from 'dashboard/helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

// Support SLA targets (docs/p9/03-sla-workflow.md). Administrator-only, matching the endpoints: configuring a
// target is an account-wide commitment, not a per-case decision, so it follows the administrator boundary
// rather than `support_ticket_manage`.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/support/sla-policies'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'support_sla_policies_index', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'support_sla_policies_index',
          meta: {
            featureFlag: FEATURE_FLAGS.LYNOMIA_SUPPORT_TICKETS,
            permissions: ['administrator'],
          },
          component: Index,
        },
      ],
    },
  ],
};
