import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import AuditLogsHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/audit-logs'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'auditlogs_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'auditlogs_list',
          meta: {
            reuseOnQueryChange: true,
            // Lynomia's own feature, gated by the `audit_logs` account flag and the administrator
            // permission. No installationTypes: Chatwoot gated this page on cloud-or-enterprise, and
            // with the Enterprise overlay gone there is no enterprise installation type to name.
            featureFlag: FEATURE_FLAGS.AUDIT_LOGS,
            permissions: ['administrator'],
          },
          component: AuditLogsHome,
        },
      ],
    },
  ],
};
