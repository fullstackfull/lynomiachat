import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/commerce.json';
import CommerceAPI from 'dashboard/api/commerce';
import StoresyriaConnectDialog from '../StoresyriaConnectDialog.vue';

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
    '<div><h1>{{ title }}</h1><p>{{ description }}</p><slot /><button data-test-id="confirm" @click="$emit(\'confirm\')" /></div>',
};

const mountDialog = (store = null) =>
  mount(StoresyriaConnectDialog, {
    props: { show: true, store },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        brandingStore,
      ],
      stubs: { Dialog: DialogStub },
    },
  });

const TOKEN = `lsc_4_1_${'a'.repeat(64)}`;

describe('StoresyriaConnectDialog', () => {
  it('sends the store address and the token, and nothing that names a store', async () => {
    CommerceAPI.create.mockResolvedValue({ data: { id: 7 } });
    const wrapper = mountDialog();
    const inputs = wrapper.findAll('input');
    await inputs[0].setValue('https://storesyria.example.com');
    await inputs[1].setValue('Damascus Store');
    await inputs[2].setValue(TOKEN);
    await wrapper.find('[data-test-id="confirm"]').trigger('click');
    await flushPromises();

    // The token names the store on Store Syria's side, so there is no store id here to get wrong or to tamper with.
    expect(CommerceAPI.create).toHaveBeenCalledWith({
      provider: 'storesyria',
      base_url: 'https://storesyria.example.com',
      name: 'Damascus Store',
      commerce_token: TOKEN,
    });
    expect(wrapper.emitted('saved')).toEqual([[{ id: 7 }]]);
  });

  it('says the integration only reads, and where the token comes from', () => {
    const wrapper = mountDialog();

    expect(wrapper.text()).toContain('It never writes to the store.');
    expect(wrapper.find('[data-test-id="storesyria-steps"]').text()).toContain(
      'Issue a commerce credential'
    );
  });

  // Replacing the token must not offer the address again: a connected store's identity is already settled, and the
  // new token has to be for that same store or the health check refuses it.
  it('replaces only the token of a connected store', async () => {
    CommerceAPI.update.mockResolvedValue({ data: { id: 7 } });
    const wrapper = mountDialog({ id: 7 });

    expect(wrapper.find('h1').text()).toBe('Replace the integration token');
    const inputs = wrapper.findAll('input');
    expect(inputs).toHaveLength(1);

    await inputs[0].setValue(TOKEN);
    await wrapper.find('[data-test-id="confirm"]').trigger('click');
    await flushPromises();

    expect(CommerceAPI.update).toHaveBeenCalledWith(7, {
      commerce_token: TOKEN,
    });
  });
});
