import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/commerce.json';
import ar from 'dashboard/i18n/locale/ar/commerce.json';
import CommerceAPI from 'dashboard/api/commerce';
import CommerceOrderSearch from '../CommerceOrderSearch.vue';

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
  default: { searchOrders: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const stubs = {
  Button: {
    props: { label: { type: String, default: '' } },
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label }}</button>',
  },
  Input: {
    props: { modelValue: { type: String, default: '' } },
    emits: ['update:modelValue', 'enter'],
    template:
      '<input :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" @keyup.enter="$emit(\'enter\')" />',
  },
};

const woo = { id: 1, name: 'Syria Cosmetics', provider: 'woocommerce' };
const salla = { id: 2, name: 'Salla Store', provider: 'salla' };
const order = {
  provider: 'woocommerce',
  external_order_id: '26',
  order_number: '26',
  status: 'shipped',
  payment_status: 'paid',
  currency: 'SAR',
  total: '100.00',
  created_at: '2026-09-29T08:00:00Z',
  item_count: 1,
  shipping: null,
  shipments: [],
  tracking: { number: 'TRK1', url: 'https://track.example.com/TRK1' },
  admin_order_url: null,
  store: woo,
};

const mountSearch = (props = {}, locale = 'en') =>
  mount(CommerceOrderSearch, {
    props: { conversationId: 7, ...props },
    global: {
      plugins: [
        createI18n({ legacy: false, locale, messages: { en, ar } }),
        brandingStore,
      ],
      stubs,
    },
  });

const searchFor = async (wrapper, number) => {
  await wrapper
    .find('[data-test-id="commerce-order-search-toggle"]')
    .trigger('click');
  await wrapper.find('input').setValue(number);
  await wrapper.find('input').trigger('keyup.enter');
  await flushPromises();
};

describe('CommerceOrderSearch', () => {
  beforeEach(() => vi.clearAllMocks());

  it('searches every store, lists the orders with their store, and says which stores were not searched', async () => {
    CommerceAPI.searchOrders.mockResolvedValue({
      data: {
        orders: [order],
        stores: [
          { store: woo, state: 'searched', error: null },
          { store: salla, state: 'unsupported', error: null },
        ],
        partial: false,
      },
    });
    const wrapper = mountSearch();

    await searchFor(wrapper, ' #26 ');

    expect(CommerceAPI.searchOrders).toHaveBeenCalledWith(7, '#26', null);
    expect(wrapper.findAll('[data-test-id="commerce-order"]')).toHaveLength(1);
    expect(wrapper.text()).toContain('#26');
    expect(wrapper.text()).toContain('Syria Cosmetics · WooCommerce');
    expect(
      wrapper.find('[data-test-id="commerce-order-search-notice"]').text()
    ).toBe("Salla Store: order search isn't available for this store");
    // A found order may be another customer's: nothing is offered for sending into the conversation.
    expect(wrapper.text()).not.toContain('Send tracking');
  });

  it('searches the open store only, and says when nothing has this number', async () => {
    CommerceAPI.searchOrders.mockResolvedValue({
      data: {
        orders: [],
        stores: [{ store: woo, state: 'searched', error: null }],
        partial: false,
      },
    });
    const wrapper = mountSearch({ storeId: 1 }, 'ar');

    await searchFor(wrapper, '99');

    expect(CommerceAPI.searchOrders).toHaveBeenCalledWith(7, '99', 1);
    expect(
      wrapper.find('[data-test-id="commerce-order-search-empty"]').text()
    ).toBe('لا يوجد طلب بهذا الرقم');
  });

  it('explains an invalid number and the search limit', async () => {
    const wrapper = mountSearch();
    CommerceAPI.searchOrders.mockRejectedValueOnce({
      response: { status: 422, data: { error: { code: 'INVALID_QUERY' } } },
    });
    await searchFor(wrapper, 'abc');
    expect(wrapper.text()).toContain(
      'Enter an order number using digits only.'
    );

    CommerceAPI.searchOrders.mockRejectedValueOnce({
      response: {
        status: 429,
        data: { error: { code: 'RATE_LIMITED', retry_after: 42 } },
      },
    });
    await wrapper.find('input').trigger('keyup.enter');
    await flushPromises();
    expect(wrapper.text()).toContain('Too many searches. Try again in 42 s.');
  });
});
