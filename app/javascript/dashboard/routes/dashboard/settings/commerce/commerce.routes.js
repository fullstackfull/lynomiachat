import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

// Lynomia Commerce store connections (administrators, `lynomia_commerce` accounts).
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/commerce'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_commerce_index',
          component: Index,
          meta: {
            featureFlag: FEATURE_FLAGS.LYNOMIA_COMMERCE,
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
