import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/commerce.json';
import CommerceAPI from 'dashboard/api/commerce';
import StoreDialog from '../StoreDialog.vue';

// Commerce copy names the product through an `{installationName}` placeholder, which the components read from
// globalConfig. A deliberately unbranded name here proves the substitution happens rather than restating
// whatever this installation is currently called.
const brandingStore = createStore({
  getters: {
    'globalConfig/get': () => ({ installationName: 'Acme Desk' }),
    'globalConfig/isACustomBrandedInstance': () => true,
  },
});

vi.mock('dashboard/api/commerce', () => ({
  default: { create: vi.fn(), update: vi.fn() },
}));

const DialogStub = {
  props: ['title', 'description'],
  emits: ['confirm'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template:
    '<div><p>{{ description }}</p><slot /><button data-test-id="confirm" @click="$emit(\'confirm\')" /></div>',
};

const mountDialog = () =>
  mount(StoreDialog, {
    props: { show: true },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        brandingStore,
      ],
      stubs: { Dialog: DialogStub },
    },
  });

describe('StoreDialog', () => {
  it('guides the key to create from the access chosen, Read/Write by default', async () => {
    const wrapper = mountDialog();
    const steps = () =>
      wrapper.find('[data-test-id="commerce-store-steps"]').text();

    expect(steps()).toContain('set Permissions to “Read/Write”');
    expect(
      wrapper
        .find('[data-test-id="commerce-store-access-read_write"]')
        .attributes('aria-pressed')
    ).toBe('true');

    await wrapper
      .find('[data-test-id="commerce-store-access-read"]')
      .trigger('click');
    expect(steps()).toContain('set Permissions to “Read”.');
    expect(steps()).toContain(
      'Open WooCommerce → Settings → Advanced → REST API'
    );
  });

  it('sends only the store and its keys: the access choice is guidance, WooCommerce decides what the key can do', async () => {
    CommerceAPI.create.mockResolvedValue({ data: { id: 1 } });
    const wrapper = mountDialog();
    const inputs = wrapper.findAll('input');
    await inputs[0].setValue('https://shop.example.com');
    await inputs[2].setValue(`ck_${'a'.repeat(40)}`);
    await inputs[3].setValue(`cs_${'b'.repeat(40)}`);
    await wrapper.find('[data-test-id="confirm"]').trigger('click');
    await flushPromises();

    expect(CommerceAPI.create).toHaveBeenCalledWith({
      provider: 'woocommerce',
      base_url: 'https://shop.example.com',
      name: '',
      consumer_key: `ck_${'a'.repeat(40)}`,
      consumer_secret: `cs_${'b'.repeat(40)}`,
    });
    expect(wrapper.emitted('saved')).toEqual([[{ id: 1 }]]);
  });
});
