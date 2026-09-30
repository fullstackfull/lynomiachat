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
