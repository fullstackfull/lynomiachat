import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';
import FlowBuilder from './FlowBuilder.vue';

// Lynomia Flow Builder (administrators, `lynomia_flow_builder` accounts). The builder takes the whole page, outside
// the settings column.
const meta = {
  featureFlag: FEATURE_FLAGS.LYNOMIA_FLOW_BUILDER,
  permissions: ['administrator'],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/flows'),
      component: SettingsWrapper,
      children: [
        { path: '', name: 'settings_flows_index', component: Index, meta },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/flows/:flowId'),
      name: 'settings_flows_builder',
      component: FlowBuilder,
      meta,
    },
  ],
};
