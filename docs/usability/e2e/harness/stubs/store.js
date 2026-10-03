import { computed, ref } from 'vue';
import { FIXTURES } from './fixtures';

export const dispatched = ref([]);

// The dialog teleports to <body> and takes its direction from this getter, not from the DOM
// (components-next/TeleportWithDirection.vue), so the harness has to answer it for the Arabic run to be real.
const isRTL = new URLSearchParams(window.location.search).get('locale') === 'ar';

const GETTERS = {
  getCurrentAccountId: () => FIXTURES.accountId,
  'accounts/isRTL': () => isRTL,
  'teams/getTeams': () => FIXTURES.teams,
  'labels/getLabels': () => FIXTURES.labels,
  'customViews/getContactCustomViews': () => FIXTURES.contactViews,
  'inboxes/getWhatsAppInboxes': () => FIXTURES.whatsAppInboxes,
  'customViews/getUIFlags': () => ({ isCreating: false }),
  'contacts/getUIFlags': () => ({}),
  'attributes/getContactAttributes': () => [],
  'contacts/getAppliedContactFiltersV4': () => [],
};

export const useMapGetter = name =>
  computed(() => (GETTERS[name] ? GETTERS[name]() : undefined));

export const useStoreGetters = () =>
  Object.fromEntries(
    Object.keys(GETTERS).map(name => [name, computed(() => GETTERS[name]())])
  );

export const useStore = () => ({
  dispatch: (action, payload) => {
    dispatched.value.push({ action, payload });
    return Promise.resolve(
      action === 'automations/create' ? { id: 42, ...payload } : undefined
    );
  },
});
