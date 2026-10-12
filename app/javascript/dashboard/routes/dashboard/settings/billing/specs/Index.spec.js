import { shallowMount } from '@vue/test-utils';
import { nextTick, ref } from 'vue';

import ProviderIndex from '../ProviderIndex.vue';
import SubscriptionSettings from '../../subscription/Index.vue';

const currentAccount = ref({});

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount,
  }),
}));

const mountComponent = () =>
  shallowMount(ProviderIndex, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsLayout: {
          name: 'SettingsLayout',
          props: {
            isLoading: Boolean,
            loadingMessage: String,
          },
          template: '<main><slot name="header" /><slot /></main>',
        },
      },
    },
  });

// Lynomia has one billing provider, its own. Chatwoot's Shopify-billed branch went with the Enterprise
// billing identity it read, so the only question left is whether the page waits for the account.
//
// What this route renders changed in P11: it used to be a component that redirected the browser to a
// hardcoded external domain (docs/p11/06-rollout-compatibility.md). It now renders the in-app billing page.
describe('Billing settings provider dispatcher', () => {
  beforeEach(() => {
    currentAccount.value = {};
  });

  it('waits for the account before mounting billing', () => {
    const wrapper = mountComponent();

    expect(wrapper.findComponent(SubscriptionSettings).exists()).toBe(false);
    expect(wrapper.findComponent({ name: 'SettingsLayout' }).props()).toEqual(
      expect.objectContaining({ isLoading: true })
    );
  });

  it('mounts billing once the account is loaded, whatever Chatwoot would have called the provider', async () => {
    const wrapper = mountComponent();
    currentAccount.value = { id: 1, billing_provider: 'shopify' };
    await nextTick();

    expect(wrapper.findComponent(SubscriptionSettings).exists()).toBe(true);
  });
});
