import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import ProviderIndex from './ProviderIndex.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/billing'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'billing_settings_index',
          component: ProviderIndex,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
