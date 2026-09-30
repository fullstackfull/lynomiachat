import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/commerce.json';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CommerceOrderItem from '../CommerceOrderItem.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const baseOrder = {
  provider: 'woocommerce',
  external_order_id: '14',
  order_number: '14',
  status: 'completed',
  provider_status: 'completed',
  payment_status: 'paid',
  currency: 'SAR',
  total: '316.00',
  created_at: '2026-08-31T08:36:53Z',
  updated_at: '2026-09-30T08:36:55Z',
  items: [],
  item_count: 3,
  customer: { external_id: '2', name: 'Layla' },
  shipping: { method: 'Aramex Express', total: '25.00' },
  tracking: null,
  admin_order_url:
    'https://shop.example.com/wp-admin/admin.php?action=edit&id=14&page=wc-orders',
  customer_order_url: null,
};

const mountOrder = order =>
  mount(CommerceOrderItem, {
    props: { order: { ...baseOrder, ...order } },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

describe('CommerceOrderItem', () => {
  it('shows number, total, statuses, item count, shipping and the admin link', () => {
    const wrapper = mountOrder({});

    expect(wrapper.text()).toContain('#14');
    expect(wrapper.text()).toContain('Completed');
    expect(wrapper.text()).toContain('Paid');
    expect(wrapper.text()).toContain('3 items');
    expect(wrapper.text()).toContain('Aramex Express');
    const link = wrapper.find('a');
    expect(link.text()).toBe('View order');
    expect(link.attributes('href')).toBe(baseOrder.admin_order_url);
    expect(link.attributes('rel')).toBe('noopener noreferrer');
  });

  it('handles an order without shipping or tracking', () => {
    const wrapper = mountOrder({ shipping: null, tracking: null });

    expect(wrapper.text()).not.toContain('Aramex');
    expect(wrapper.text()).not.toContain('Track shipment');
    expect(wrapper.text()).not.toContain('Send tracking');
  });

  it('shows a shipped order with its carrier and shipment status the same way for any provider', () => {
    const wrapper = mountOrder({
      provider: 'salla',
      status: 'shipped',
      payment_status: 'unknown',
      item_count: 5,
      shipping: {
        method: 'Aramex, SMSA',
        total: null,
        provider: 'Aramex',
        status: 'in_transit',
      },
      shipments: [
        { provider: 'Aramex', status: 'in_transit', type: 'shipment' },
        { provider: 'SMSA', status: 'out_for_delivery', type: 'shipment' },
      ],
      tracking: {
        number: 'AX123456789SA',
        url: 'https://www.aramex.com/track/results?ShipmentNumber=AX123456789SA',
      },
    });

    expect(wrapper.text()).toContain('Shipped');
    expect(wrapper.text()).toContain('Aramex, SMSA');
    expect(wrapper.find('[data-test-id="commerce-shipment"]').text()).toBe(
      'In transit'
    );
    expect(wrapper.text()).toContain('Track shipment');
    expect(wrapper.text()).toContain('Send tracking');
  });

  it('leaves the item count out when the store did not send the items', () => {
    expect(mountOrder({ item_count: null }).text()).not.toContain('items');
  });

  it('never claims payment it cannot confirm', () => {
    expect(mountOrder({ payment_status: 'unknown' }).text()).toContain(
      'Payment not confirmed'
    );
  });

  it('does not link to unsafe tracking or admin URLs', () => {
    const wrapper = mountOrder({
      // eslint-disable-next-line no-script-url -- a script URL is the input under test
      admin_order_url: 'javascript:alert(1)',
      tracking: { number: null, url: 'http://track.example.com' },
    });

    expect(wrapper.findAll('a')).toHaveLength(0);
    expect(wrapper.text()).not.toContain('Send tracking');
  });

  it('inserts tracking into the reply box without sending anything', async () => {
    const inserted = vi.fn();
    emitter.on(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, inserted);
    const wrapper = mountOrder({
      tracking: { number: 'ARX123', url: 'https://track.example.com/ARX123' },
    });

    expect(
      wrapper.find('a[href="https://track.example.com/ARX123"]').text()
    ).toBe('Track shipment');
    await wrapper.findAll('button').at(-1).trigger('click');

    expect(inserted).toHaveBeenCalledWith(
      'Your order #14 is on its way. Tracking number: ARX123. Track it here: https://track.example.com/ARX123'
    );
    emitter.off(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, inserted);
  });
});
