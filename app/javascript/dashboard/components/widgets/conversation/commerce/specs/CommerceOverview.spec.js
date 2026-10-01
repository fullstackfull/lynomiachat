import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/commerce.json';
import ar from 'dashboard/i18n/locale/ar/commerce.json';
import CommerceOverview from '../CommerceOverview.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const stubs = {
  Button: {
    props: { label: { type: String, default: '' } },
    emits: ['click'],
    template: '<button @click="$emit(\'click\')">{{ label }}</button>',
  },
};

const minutesAgo = minutes =>
  new Date(Date.now() - minutes * 60 * 1000).toISOString();
const entry = (id, name, provider, attrs = {}) => ({
  store: { id, name, provider },
  state: 'linked',
  link: { match_source: 'verified_phone', customer_type: 'registered' },
  fetched_at: minutesAgo(1),
  stale: false,
  error: null,
  orders_count: 1,
  ...attrs,
});
const order = (number, store, attrs = {}) => ({
  provider: store.provider,
  external_order_id: number,
  order_number: number,
  status: 'shipped',
  payment_status: 'paid',
  currency: 'SAR',
  total: '220.00',
  created_at: '2026-09-29T08:00:00Z',
  item_count: 1,
  shipping: null,
  shipments: [],
  tracking: null,
  admin_order_url: null,
  store,
  ...attrs,
});
const salla = { id: 1, name: 'Syria Cosmetics', provider: 'salla' };
const shopify = { id: 3, name: 'Global', provider: 'shopify' };

const overview = (attrs = {}) => ({
  contact: { id: 9 },
  stores_count: 3,
  linked_stores_count: 2,
  orders_count_visible: 2,
  total_spend_visible: [
    { currency: 'SAR', amount: '2450.00' },
    { currency: 'USD', amount: '380.00' },
  ],
  currencies: ['SAR', 'USD'],
  last_order_at: minutesAgo(2 * 24 * 60),
  active_orders_count: 1,
  shipped_orders_count: 1,
  latest_orders: [
    order('1234', salla),
    order('8891', shopify, { currency: 'USD', total: '95.00' }),
  ],
  stores: [
    entry(1, 'Syria Cosmetics', 'salla'),
    entry(2, 'Main Shop', 'woocommerce', {
      link: { match_source: 'manual', customer_type: 'guest' },
    }),
    entry(3, 'Global', 'shopify', {
      state: 'linked',
      stale: true,
      error: 'TIMEOUT',
      fetched_at: minutesAgo(18),
    }),
  ],
  partial: true,
  ...attrs,
});

const mountOverview = (data, locale = 'en') =>
  mount(CommerceOverview, {
    props: { overview: data },
    global: {
      plugins: [createI18n({ legacy: false, locale, messages: { en, ar } })],
      stubs,
    },
  });

describe('CommerceOverview', () => {
  it('shows the visible figures, spend per currency and each order source', () => {
    const wrapper = mountOverview(overview());
    const text = wrapper.text();

    expect(text).toContain('3 connected');
    expect(text).toContain('2 linked');
    expect(text).toContain('2 visible');
    expect(text).toContain('2 days ago');
    const spend = wrapper
      .findAll('[data-test-id="commerce-overview-spend"]')
      .map(node => node.text().replace(/\s/g, ' '));
    expect(spend).toEqual(['SAR 2,450.00', '$380.00']);
    const sources = wrapper
      .findAll('[data-test-id="commerce-order-store"]')
      .map(node => node.text());
    expect(sources).toEqual(['Syria Cosmetics · Salla', 'Global · Shopify']);
  });

  it('reports a partial refresh and each store freshness separately', () => {
    const wrapper = mountOverview(overview());

    expect(
      wrapper.find('[data-test-id="commerce-overview-partial"]').text()
    ).toBe("Some stores couldn't be refreshed");
    const freshness = wrapper
      .findAll('[data-test-id="commerce-overview-freshness"]')
      .map(node => node.text());
    expect(freshness[0]).toBe('Updated 1 minute ago');
    expect(freshness[2]).toBe('Showing data from 18 minutes ago');
    expect(wrapper.text()).toContain('Guest checkout · Linked manually');
  });

  it('marks stores that need attention and does not offer to open them', () => {
    const wrapper = mountOverview(
      overview({
        stores: [
          entry(1, 'Syria Cosmetics', 'salla', { state: 'needs_reauth' }),
          entry(2, 'Main Shop', 'woocommerce', {
            state: 'provider_unavailable',
          }),
        ],
      })
    );

    expect(wrapper.text()).toContain('Store needs re-authorization');
    expect(wrapper.text()).toContain('Provider currently unavailable');
    expect(
      wrapper.findAll('button').filter(button => button.text() === 'Open store')
    ).toHaveLength(0);
  });

  it('explains an unlinked customer and a customer without orders', () => {
    const notLinked = mountOverview(
      overview({
        linked_stores_count: 0,
        orders_count_visible: 0,
        total_spend_visible: [],
        last_order_at: null,
        latest_orders: [],
        partial: false,
      })
    );
    expect(
      notLinked.find('[data-test-id="commerce-overview-not-linked"]').text()
    ).toContain('Customer not linked');
    expect(notLinked.text()).toContain('No paid orders');

    const noOrders = mountOverview(
      overview({ latest_orders: [], last_order_at: null })
    );
    expect(
      noOrders.find('[data-test-id="commerce-overview-last-purchase"]').text()
    ).toBe('No orders found');
  });

  it('asks to open a store', async () => {
    const wrapper = mountOverview(overview());
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Open store')
      .trigger('click');

    expect(wrapper.emitted('openStore')).toEqual([[1]]);
  });

  it('renders in Arabic', () => {
    const text = mountOverview(overview(), 'ar').text();

    expect(text).toContain('تعذر تحديث بعض المتاجر');
    expect(text).toContain('آخر شراء');
    expect(text).toContain('أحدث الطلبات');
  });
});
