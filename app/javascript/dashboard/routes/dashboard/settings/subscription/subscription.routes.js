import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

// Custom subscription page (self-hosted billing)
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/subscription'),
      meta: {
        permissions: ['administrator', 'agent'],
      },
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'subscription_settings_index',
          component: Index,
          meta: {
            permissions: ['administrator', 'agent'],
          },
        },
      ],
    },
  ],
};
