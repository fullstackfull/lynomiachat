import { frontendURL } from '../../../helper/URLHelper';
import ContactsIndex from './pages/ContactsIndex.vue';
import AudiencesIndex from './pages/AudiencesIndex.vue';
import ContactManageView from './pages/ContactManageView.vue';
import { FEATURE_FLAGS } from '../../../featureFlags';

const commonMeta = {
  featureFlag: FEATURE_FLAGS.CRM,
  permissions: ['administrator', 'agent', 'contact_manage'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/contacts'),
    component: ContactsIndex,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'contacts_dashboard_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'segments/:segmentId',
        name: 'contacts_dashboard_segments_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'labels/:label',
        name: 'contacts_dashboard_labels_index',
        component: ContactsIndex,
        meta: commonMeta,
      },
      {
        path: 'active',
        name: 'contacts_dashboard_active',
        component: ContactsIndex,
        meta: commonMeta,
      },
    ],
  },
  // The audiences destination, a route of its own rather than a child of the list above: that parent renders
  // ContactsIndex itself and has no `<router-view>`, so a child component would never be reached. Its static path
  // also outranks `:contactId` below, so it can never be read as a contact id.
  {
    path: frontendURL('accounts/:accountId/contacts/audiences'),
    name: 'contacts_dashboard_audiences_index',
    component: AudiencesIndex,
    meta: commonMeta,
  },
  {
    path: frontendURL('accounts/:accountId/contacts/:contactId'),
    component: ContactManageView,
    meta: commonMeta,
    children: [
      {
        path: '',
        name: 'contacts_edit',
        component: ContactManageView,
        meta: commonMeta,
      },
      {
        path: 'segments/:segmentId',
        name: 'contacts_edit_segment',
        component: ContactManageView,
        meta: commonMeta,
      },
      {
        path: 'labels/:label',
        name: 'contacts_edit_label',
        component: ContactManageView,
        meta: commonMeta,
      },
    ],
  },
];
