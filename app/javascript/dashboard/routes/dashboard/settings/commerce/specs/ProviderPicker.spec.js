import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/commerce.json';
import ProviderPicker from '../ProviderPicker.vue';

// Commerce copy names the product through an `{installationName}` placeholder, which the components read from
// globalConfig. A deliberately unbranded name here proves the substitution happens rather than restating
// whatever this installation is currently called.
const brandingStore = createStore({
  getters: {
    'globalConfig/get': () => ({ installationName: 'Acme Desk' }),
    'globalConfig/isACustomBrandedInstance': () => true,
  },
});

const DialogStub = {
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /></div>',
};

const mountPicker = providers =>
  mount(ProviderPicker, {
    props: { show: true, providers },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        brandingStore,
      ],
      stubs: { Dialog: DialogStub, Icon: true },
    },
  });

describe('ProviderPicker', () => {
  it('offers WooCommerce and Salla when the installation has both', async () => {
    const wrapper = mountPicker(['woocommerce', 'salla']);

    expect(wrapper.text()).toContain('WooCommerce');
    expect(wrapper.text()).toContain('Salla');
    await wrapper
      .find('[data-test-id="commerce-provider-salla"]')
      .trigger('click');

    expect(wrapper.emitted('select')).toEqual([['salla']]);
  });

  it('offers Zid next to WooCommerce and Salla', async () => {
    const wrapper = mountPicker(['woocommerce', 'salla', 'zid']);

    expect(wrapper.text()).toContain('Zid');
    expect(wrapper.text()).toContain('Authorize the Acme Desk app on Zid.');
    await wrapper
      .find('[data-test-id="commerce-provider-zid"]')
      .trigger('click');

    expect(wrapper.emitted('select')).toEqual([['zid']]);
  });

  it('offers Shopify next to the other providers', async () => {
    const wrapper = mountPicker(['woocommerce', 'salla', 'zid', 'shopify']);

    expect(wrapper.text()).toContain('Shopify');
    expect(wrapper.text()).toContain(
      'Authorize the Acme Desk Commerce app on your Shopify store.'
    );
    await wrapper
      .find('[data-test-id="commerce-provider-shopify"]')
      .trigger('click');

    expect(wrapper.emitted('select')).toEqual([['shopify']]);
  });

  it('lists every platform, and a platform the installation does not offer cannot be chosen', async () => {
    const wrapper = mountPicker(['woocommerce']);
    const salla = wrapper.find('[data-test-id="commerce-provider-salla"]');

    expect(salla.exists()).toBe(true);
    expect(salla.attributes('disabled')).toBeDefined();
    expect(salla.text()).toContain('Not available yet');
    expect(wrapper.text()).toContain(
      'Platforms marked “Not available yet” aren’t offered on this workspace yet.'
    );
    await salla.trigger('click');
    expect(wrapper.emitted('select')).toBeUndefined();

    const woo = wrapper.find('[data-test-id="commerce-provider-woocommerce"]');
    expect(woo.attributes('disabled')).toBeUndefined();
    expect(woo.text()).toContain(
      'Read/Write for live updates and order actions'
    );
  });
});
