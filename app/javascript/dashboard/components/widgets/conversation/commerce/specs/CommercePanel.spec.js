import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/commerce.json';
import ar from 'dashboard/i18n/locale/ar/commerce.json';
import CommerceAPI from 'dashboard/api/commerce';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CommercePanel from '../CommercePanel.vue';

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
  default: {
    getConversationStores: vi.fn(),
    getOverview: vi.fn(),
    getPanel: vi.fn(),
    searchCustomers: vi.fn(),
    linkCustomer: vi.fn(),
    unlinkCustomer: vi.fn(),
    refresh: vi.fn(),
  },
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: { value: true } }),
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
      '<input :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
  },
  Select: {
    props: {
      modelValue: { type: Number, default: null },
      options: { type: Array, default: () => [] },
    },
    emits: ['update:modelValue'],
    template:
      '<select data-test-id="store-select" @change="$emit(\'update:modelValue\', $event.target.value)"><option v-for="o in options" :key="o.value" :value="o.value">{{ o.label }}</option></select>',
  },
  Spinner: { template: '<span>loading</span>' },
};

const order = number => ({
  provider: 'woocommerce',
  external_order_id: number,
  order_number: number,
  status: 'processing',
  provider_status: 'processing',
  payment_status: 'paid',
  currency: 'SAR',
  total: '100.00',
  created_at: '2026-09-29T08:00:00Z',
  updated_at: '2026-09-29T08:00:00Z',
  items: [],
  item_count: 1,
  customer: { external_id: '2', name: 'Layla' },
  shipping: null,
  tracking: null,
  admin_order_url: `https://shop.example.com/wp-admin/admin.php?id=${number}`,
  customer_order_url: null,
});

const store = { id: 1, name: 'Syria Cosmetics', provider: 'woocommerce' };
const linkedPanel = {
  store,
  state: 'linked',
  link: { match_source: 'verified_phone', linked_at: 1, confirmed_by: null },
  orders: ['26', '25', '24', '23', '22'].map(order),
  fetched_at: new Date().toISOString(),
  stale: false,
  error: null,
};

// Panels listen on the app-wide emitter, so each test unmounts the ones it mounted.
const mounted = [];
const mountPanel = (locale = 'en') => {
  const wrapper = mount(CommercePanel, {
    props: { conversationId: 7, contactId: 3 },
    global: {
      plugins: [
        createI18n({ legacy: false, locale, messages: { en, ar } }),
        brandingStore,
      ],
      stubs,
    },
  });
  mounted.push(wrapper);
  return wrapper;
};

const respond = (stores, panel) => {
  CommerceAPI.getConversationStores.mockResolvedValue({
    data: { payload: stores },
  });
  CommerceAPI.getPanel.mockResolvedValue({ data: panel });
};

const overview = {
  contact: { id: 3 },
  stores_count: 2,
  linked_stores_count: 2,
  orders_count_visible: 2,
  total_spend_visible: [{ currency: 'SAR', amount: '100.00' }],
  currencies: ['SAR'],
  last_order_at: '2026-09-29T08:00:00Z',
  active_orders_count: 1,
  shipped_orders_count: 0,
  latest_orders: [{ ...order('26'), store }],
  stores: [
    {
      store,
      state: 'linked',
      link: { match_source: 'verified_phone', customer_type: 'guest' },
      fetched_at: new Date().toISOString(),
      stale: false,
      error: null,
      orders_count: 1,
    },
  ],
  partial: false,
};
const sallaStore = { id: 2, name: 'Second store', provider: 'salla' };

describe('CommercePanel', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.localStorage.clear();
  });
  afterEach(() => mounted.splice(0).forEach(wrapper => wrapper.unmount()));

  it('explains when no store is connected', async () => {
    respond([], null);
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('No store is connected yet.');
    expect(CommerceAPI.getPanel).not.toHaveBeenCalled();
  });

  it('shows the linked customer and the latest five orders', async () => {
    respond([{ ...store, linked: true }], linkedPanel);
    const wrapper = mountPanel();
    await flushPromises();

    expect(CommerceAPI.getPanel).toHaveBeenCalledWith(7, 1, expect.any(Object));
    expect(wrapper.text()).toContain(
      'Matched by the verified phone of this conversation'
    );
    expect(wrapper.findAll('[data-test-id="commerce-order"]')).toHaveLength(5);
    expect(wrapper.find('[data-test-id="store-select"]').exists()).toBe(false);
  });

  it('offers a link action when the customer is not in the store', async () => {
    respond([{ ...store, linked: false }], {
      store,
      state: 'not_found',
      candidates: [],
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('Customer not found in this store');
    expect(wrapper.text()).toContain('Link customer');
  });

  it('marks stale data with its age instead of presenting it as live', async () => {
    const fetchedAt = new Date(Date.now() - 18 * 60 * 1000).toISOString();
    respond([{ ...store, linked: true }], {
      ...linkedPanel,
      stale: true,
      error: 'TIMEOUT',
      fetched_at: fetchedAt,
    });
    const wrapper = mountPanel();
    await flushPromises();

    const banner = wrapper.find('[data-test-id="commerce-stale"]').text();
    expect(banner).toContain("Couldn't refresh store data right now.");
    expect(banner).toContain('Last updated 18 minutes ago');
  });

  it('links a suggested candidate through its token', async () => {
    const candidate = {
      token: 'tok',
      name: 'Omar Khalil',
      email: 'om***@example.com',
      phone: null,
      registered: false,
    };
    respond([{ ...store, linked: false }], {
      store,
      state: 'suggested',
      candidates: [candidate],
    });
    CommerceAPI.linkCustomer.mockResolvedValue({ data: linkedPanel });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('Possible match. Confirm before linking.');
    expect(wrapper.text()).toContain('om***@example.com');
    const linkButton = wrapper
      .findAll('button')
      .find(button => button.text() === 'Link');
    await linkButton.trigger('click');
    await flushPromises();

    expect(CommerceAPI.linkCustomer).toHaveBeenCalledWith(7, 1, 'tok');
    expect(wrapper.findAll('[data-test-id="commerce-order"]')).toHaveLength(5);
  });

  it('lets the agent pick a store when several are connected, never mixing them', async () => {
    const second = {
      id: 2,
      name: 'Second store',
      provider: 'woocommerce',
      linked: false,
    };
    respond([{ ...store, linked: false }, second], {
      store,
      state: 'not_found',
      candidates: [],
    });
    const wrapper = mountPanel();
    await flushPromises();

    CommerceAPI.getPanel.mockResolvedValue({
      data: { ...linkedPanel, store: second },
    });
    await wrapper.find('[data-test-id="store-select"]').setValue('2');
    await flushPromises();

    expect(CommerceAPI.getPanel).toHaveBeenLastCalledWith(
      7,
      2,
      expect.any(Object)
    );
    expect(wrapper.findAll('[data-test-id="commerce-order"]')).toHaveLength(5);
    expect(wrapper.text()).not.toContain('Customer not found in this store');
  });

  it('renders in Arabic', async () => {
    const fetchedAt = new Date(Date.now() - 18 * 60 * 1000).toISOString();
    respond([{ ...store, linked: false }], {
      store,
      state: 'not_found',
      candidates: [],
      stale: true,
      error: 'TIMEOUT',
      fetched_at: fetchedAt,
    });
    const wrapper = mountPanel('ar');
    await flushPromises();

    expect(wrapper.text()).toContain('لم يتم العثور على العميل في هذا المتجر');
    expect(wrapper.text()).toContain('ربط العميل');
    expect(wrapper.text()).toContain('تعذر تحديث البيانات حاليًا');
    expect(wrapper.text()).toContain('آخر تحديث');
  });

  it('shows a safe message, never the raw provider error, when the store is unavailable', async () => {
    respond([{ ...store, linked: true }], {
      store,
      state: 'unavailable',
      error: 'AUTH_INVALID',
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain(
      "The store rejected Acme Desk's credentials."
    );
  });

  describe('Customer 360', () => {
    it('opens on the overview for a contact linked in several stores', async () => {
      respond(
        [
          { ...store, linked: true },
          { ...sallaStore, linked: true },
        ],
        linkedPanel
      );
      CommerceAPI.getOverview.mockResolvedValue({ data: overview });
      const wrapper = mountPanel();
      await flushPromises();

      expect(CommerceAPI.getOverview).toHaveBeenCalledWith(
        7,
        expect.any(Object)
      );
      expect(CommerceAPI.getPanel).not.toHaveBeenCalled();
      expect(wrapper.find('[data-test-id="commerce-overview"]').exists()).toBe(
        true
      );
      expect(
        wrapper.find('[data-test-id="commerce-order-store"]').text()
      ).toContain('Syria Cosmetics · WooCommerce');
    });

    it('keeps the store view for a single store, with no views to switch', async () => {
      respond([{ ...store, linked: true }], linkedPanel);
      const wrapper = mountPanel();
      await flushPromises();

      expect(wrapper.find('[data-test-id="commerce-views"]').exists()).toBe(
        false
      );
      expect(CommerceAPI.getOverview).not.toHaveBeenCalled();
    });

    it('opens a store from the overview and remembers the agent choice', async () => {
      respond(
        [
          { ...store, linked: true },
          { ...sallaStore, linked: true },
        ],
        linkedPanel
      );
      CommerceAPI.getOverview.mockResolvedValue({ data: overview });
      const wrapper = mountPanel();
      await flushPromises();

      const open = wrapper
        .findAll('button')
        .find(button => button.text() === 'Open store');
      await open.trigger('click');
      await flushPromises();

      expect(CommerceAPI.getPanel).toHaveBeenCalledWith(
        7,
        1,
        expect.any(Object)
      );
      expect(wrapper.findAll('[data-test-id="commerce-order"]')).toHaveLength(
        5
      );
      expect(window.localStorage.getItem('lynomia.commerce.view')).toBe(
        'store'
      );

      vi.clearAllMocks();
      mountPanel();
      await flushPromises();
      expect(CommerceAPI.getOverview).not.toHaveBeenCalled();
      expect(CommerceAPI.getPanel).toHaveBeenCalled();
    });
  });

  describe('live updates and refresh', () => {
    afterEach(() => vi.useRealTimers());

    it('refetches the open store view when this contact changes in that store, once per burst', async () => {
      vi.useFakeTimers();
      respond([{ ...store, linked: true }], linkedPanel);
      mountPanel();
      await flushPromises();
      CommerceAPI.getPanel.mockClear();

      emitter.emit(BUS_EVENTS.COMMERCE_CUSTOMER_UPDATED, {
        contact_id: 3,
        store_id: 1,
      });
      emitter.emit(BUS_EVENTS.COMMERCE_CUSTOMER_UPDATED, {
        contact_id: 3,
        store_id: 1,
      });
      emitter.emit(BUS_EVENTS.COMMERCE_CUSTOMER_UPDATED, {
        contact_id: 4,
        store_id: 1,
      });
      emitter.emit(BUS_EVENTS.COMMERCE_CUSTOMER_UPDATED, {
        contact_id: 3,
        store_id: 2,
      });
      vi.advanceTimersByTime(600);
      await flushPromises();

      expect(CommerceAPI.getPanel).toHaveBeenCalledTimes(1);
    });

    it('refetches the overview for any store of this contact', async () => {
      vi.useFakeTimers();
      respond(
        [
          { ...store, linked: true },
          { ...sallaStore, linked: true },
        ],
        linkedPanel
      );
      CommerceAPI.getOverview.mockResolvedValue({ data: overview });
      mountPanel();
      await flushPromises();
      CommerceAPI.getOverview.mockClear();

      emitter.emit(BUS_EVENTS.COMMERCE_CUSTOMER_UPDATED, {
        contact_id: 3,
        store_id: 2,
      });
      vi.advanceTimersByTime(600);
      await flushPromises();

      expect(CommerceAPI.getOverview).toHaveBeenCalledTimes(1);
      expect(CommerceAPI.getPanel).not.toHaveBeenCalled();
    });

    it('reads the open view again after the socket reconnects', async () => {
      respond([{ ...store, linked: true }], linkedPanel);
      mountPanel();
      await flushPromises();
      CommerceAPI.getPanel.mockClear();

      emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
      await flushPromises();

      expect(CommerceAPI.getPanel).toHaveBeenCalledTimes(1);
    });

    it('refreshes the open view on request, and explains the cooldown', async () => {
      respond([{ ...store, linked: true }], linkedPanel);
      const wrapper = mountPanel();
      await flushPromises();

      CommerceAPI.refresh.mockResolvedValueOnce({
        data: { ...linkedPanel, orders: [order('30')] },
      });
      await wrapper.find('[data-test-id="commerce-refresh"]').trigger('click');
      await flushPromises();
      expect(CommerceAPI.refresh).toHaveBeenCalledWith(7, 1);
      expect(wrapper.findAll('[data-test-id="commerce-order"]')).toHaveLength(
        1
      );

      CommerceAPI.refresh.mockRejectedValueOnce({
        response: {
          status: 429,
          data: { error: { code: 'RATE_LIMITED', retry_after: 25 } },
        },
      });
      await wrapper.find('[data-test-id="commerce-refresh"]').trigger('click');
      await flushPromises();
      expect(
        wrapper.find('[data-test-id="commerce-refresh-notice"]').text()
      ).toBe('Just refreshed. Try again in 25 s.');
      expect(wrapper.findAll('[data-test-id="commerce-order"]')).toHaveLength(
        1
      );
    });
  });
});
