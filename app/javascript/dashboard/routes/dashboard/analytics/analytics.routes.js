import { frontendURL } from 'dashboard/helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// Analytics is account-wide reporting, so it carries the permission the product already uses for reports --
// ReportPolicy#view? is administrator-only on the server, and `report_manage` is the matching custom-role
// permission the existing report routes declare.
import ReportsWrapper from 'dashboard/routes/dashboard/settings/reports/components/ReportsWrapper.vue';
import AnalyticsOverview from './AnalyticsOverview.vue';

const meta = {
  featureFlag: FEATURE_FLAGS.REPORTS,
  permissions: ['administrator', 'report_manage'],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/analytics'),
      component: ReportsWrapper,
      children: [
        {
          path: '',
          name: 'analytics_overview',
          meta,
          component: AnalyticsOverview,
        },
      ],
    },
  ],
};
