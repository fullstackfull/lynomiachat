import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/commerce.json';
import CommerceAPI from 'dashboard/api/commerce';
import { useAlert } from 'dashboard/composables';
import CommerceOrderActions from '../CommerceOrderActions.vue';

vi.mock('dashboard/api/commerce', () => ({
  default: {
    getOrderActions: vi.fn(),
    requestOrderAction: vi.fn(),
    getActionRun: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const DialogStub = {
  props: ['title'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template:
    '<form @submit.prevent><h3>{{ title }}</h3><slot name="description" /><slot /><slot name="footer" /></form>',
};

const AVAILABILITY = {
  store: { id: 7, name: 'Woo Store', provider: 'woocommerce' },
  order: { external_order_id: '15', order_number: '15', status: 'processing' },
  version: 'a1'.repeat(16),
  actions: {
    update_order_status: { available: true, targets: ['completed', 'on_hold'] },
    cancel_order: { available: false, reason: 'paid_refund_first' },
    refund_full: {
      available: true,
      max_amount: '79.25',
      currency: 'SAR',
      mode: 'gateway',
      gateway: 'Credit card (Stripe)',
    },
    refund_partial: {
      available: true,
      max_amount: '79.25',
      currency: 'SAR',
      mode: 'gateway',
      gateway: 'Credit card (Stripe)',
    },
    resend_invoice: { available: true },
    resend_payment_link: { available: false, reason: 'order_state' },
    update_shipping: { available: false, reason: 'unsupported' },
  },
  last_run: null,
};

const mountActions = async () => {
  const wrapper = mount(CommerceOrderActions, {
    props: {
      conversationId: 3,
      storeId: 7,
      order: { external_order_id: '15', order_number: '15' },
    },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: { Dialog: DialogStub },
    },
  });
  await wrapper
    .find('[data-test-id="commerce-order-actions"]')
    .trigger('click');
  await flushPromises();
  return wrapper;
};

const click = async (wrapper, testId) => {
  await wrapper.find(`[data-test-id="${testId}"]`).trigger('click');
  await flushPromises();
};

describe('CommerceOrderActions', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    CommerceAPI.getOrderActions.mockResolvedValue({ data: AVAILABILITY });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it('reads the order now and lists what is possible, with why the rest is not, never acting from the menu', async () => {
    const wrapper = await mountActions();

    expect(CommerceAPI.getOrderActions).toHaveBeenCalledWith(3, 7, '15');
    expect(wrapper.text()).toContain('Woo Store · WooCommerce');
    expect(wrapper.text()).toContain('The order is paid: refund it first.');
    expect(wrapper.text()).not.toContain('Update shipping');
    expect(
      wrapper
        .find('[data-test-id="commerce-action-cancel_order"]')
        .attributes('disabled')
    ).toBeDefined();
    expect(CommerceAPI.requestOrderAction).not.toHaveBeenCalled();
  });

  it('refuses an amount above what is refundable before anything is sent', async () => {
    const wrapper = await mountActions();
    await click(wrapper, 'commerce-action-refund_partial');
    await wrapper.find('input').setValue('80.00');
    await click(wrapper, 'commerce-action-review-button');

    expect(wrapper.text()).toMatch(
      /Enter an amount above 0 and up to SAR\s79\.25\./
    );
    expect(
      wrapper.find('[data-test-id="commerce-action-confirm"]').exists()
    ).toBe(false);
  });

  it('shows the consequence, confirms once with one key however often it is clicked, and follows the run', async () => {
    CommerceAPI.requestOrderAction.mockResolvedValue({
      data: { id: 41, status: 'pending' },
    });
    CommerceAPI.getActionRun.mockResolvedValue({
      data: { id: 41, status: 'succeeded' },
    });
    const wrapper = await mountActions();
    await click(wrapper, 'commerce-action-refund_partial');
    await wrapper.find('input').setValue('29.25');
    await wrapper.find('input').trigger('keydown.enter');
    await wrapper.find('form').trigger('submit');
    expect(CommerceAPI.requestOrderAction).not.toHaveBeenCalled();

    await click(wrapper, 'commerce-action-review-button');
    expect(
      wrapper.find('[data-test-id="commerce-action-consequence"]').text()
    ).toMatch(
      /^SAR\s29\.25 will be sent back to the customer through Credit card \(Stripe\)\. This can’t be undone\.$/
    );
    await wrapper.find('form').trigger('submit');
    expect(CommerceAPI.requestOrderAction).not.toHaveBeenCalled();

    const confirm = wrapper.find('[data-test-id="commerce-action-confirm"]');
    confirm.trigger('click');
    confirm.trigger('click');
    await flushPromises();

    expect(CommerceAPI.requestOrderAction).toHaveBeenCalledTimes(1);
    const [, , orderId, payload] = CommerceAPI.requestOrderAction.mock.calls[0];
    expect(orderId).toBe('15');
    expect(payload).toMatchObject({
      action_type: 'refund_partial',
      version: AVAILABILITY.version,
      params: { amount: '29.25', currency: 'SAR', reason: 'customer_request' },
    });
    expect(payload.idempotency_key).toMatch(
      /^commerce-action:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    );

    await vi.advanceTimersByTimeAsync(1500);
    expect(wrapper.text()).toContain(
      'Done. The order shown is now read from the store.'
    );
    expect(wrapper.emitted('done')).toHaveLength(1);
    expect(useAlert).toHaveBeenCalledWith('Order #15 updated in Woo Store.');
  });

  it('keeps the same key when the agent tries again after an error, so the store never gets it twice', async () => {
    CommerceAPI.requestOrderAction
      .mockRejectedValueOnce({ response: { status: 502 } })
      .mockRejectedValueOnce({
        response: { status: 422, data: { error: { code: 'ORDER_CHANGED' } } },
      });
    const wrapper = await mountActions();
    await click(wrapper, 'commerce-action-update_order_status');
    await click(wrapper, 'commerce-action-review-button');
    await click(wrapper, 'commerce-action-confirm');
    await click(wrapper, 'commerce-action-confirm');

    const keys = CommerceAPI.requestOrderAction.mock.calls.map(
      call => call[3].idempotency_key
    );
    expect(new Set(keys).size).toBe(1);
    expect(CommerceAPI.requestOrderAction.mock.calls[0][3].params).toEqual({
      target_status: 'completed',
    });
    expect(wrapper.text()).toContain(
      'The order changed in the store after you opened it. Nothing was sent. Review it again.'
    );
  });

  it('says plainly when the store did not answer, and does not offer to try again', async () => {
    CommerceAPI.requestOrderAction.mockResolvedValue({
      data: { id: 42, status: 'pending' },
    });
    CommerceAPI.getActionRun.mockResolvedValue({
      data: { id: 42, status: 'unknown', error_code: 'UNKNOWN_OUTCOME' },
    });
    const wrapper = await mountActions();
    await click(wrapper, 'commerce-action-resend_invoice');
    await click(wrapper, 'commerce-action-confirm');
    await vi.advanceTimersByTimeAsync(1500);

    expect(
      wrapper.find('[data-test-id="commerce-action-result"]').text()
    ).toContain('Lynomia is checking the order with the store');
    expect(
      wrapper.find('[data-test-id="commerce-action-confirm"]').exists()
    ).toBe(false);
    expect(wrapper.emitted('done')).toBeUndefined();
  });
});
