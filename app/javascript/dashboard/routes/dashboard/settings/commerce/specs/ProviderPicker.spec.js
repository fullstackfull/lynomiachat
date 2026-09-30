import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/commerce.json';
import ProviderPicker from '../ProviderPicker.vue';

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
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
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
    expect(wrapper.text()).toContain('Authorize the Lynomia app on Zid.');
    await wrapper
      .find('[data-test-id="commerce-provider-zid"]')
      .trigger('click');

    expect(wrapper.emitted('select')).toEqual([['zid']]);
  });

  it('offers Shopify next to the other providers', async () => {
    const wrapper = mountPicker(['woocommerce', 'salla', 'zid', 'shopify']);

    expect(wrapper.text()).toContain('Shopify');
    expect(wrapper.text()).toContain(
      'Authorize the Lynomia Commerce app on your Shopify store.'
    );
    await wrapper
      .find('[data-test-id="commerce-provider-shopify"]')
      .trigger('click');

    expect(wrapper.emitted('select')).toEqual([['shopify']]);
  });

  it('never offers a provider the installation switched off', () => {
    const wrapper = mountPicker(['woocommerce']);

    expect(
      wrapper.find('[data-test-id="commerce-provider-salla"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-test-id="commerce-provider-woocommerce"]').exists()
    ).toBe(true);
  });
});
