import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/commerce.json';
import CommerceAPI from 'dashboard/api/commerce';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { mockIsAdmin } from 'dashboard/composables/useAdmin';
import CommerceCarts from '../CommerceCarts.vue';

vi.mock('dashboard/api/commerce', () => ({
  default: { getCarts: vi.fn(), prepareRecovery: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { ref } = await import('vue');
  const isAdmin = ref(false);
  return { useAdmin: () => ({ isAdmin }), mockIsAdmin: isAdmin };
});

const STORE = { id: 7, name: 'Zid Store', provider: 'zid' };
const cart = (overrides = {}) => ({
  external_cart_id: 'c0ffee01',
  created_at: new Date(Date.now() - 2 * 3600 * 1000).toISOString(),
  updated_at: new Date(Date.now() - 3600 * 1000).toISOString(),
  currency: 'SAR',
  total: '120.5',
  items: [{ name: 'Oud', quantity: 2 }],
  status: 'abandoned',
  match: 'verified_phone',
  recovery: { prepared_at: null, sent_at: null, cooldown_until: null },
  ...overrides,
});

const mountCarts = async (stores, props = {}) => {
  CommerceAPI.getCarts.mockResolvedValue({ data: { stores } });
  const wrapper = mount(CommerceCarts, {
    props: { conversationId: 3, ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });
  await flushPromises();
  return wrapper;
};

describe('CommerceCarts', () => {
  let inserted;
  const onInsert = text => {
    inserted = text;
  };

  beforeEach(() => {
    inserted = undefined;
    mockIsAdmin.value = false;
    emitter.on(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, onInsert);
  });

  afterEach(() => {
    emitter.off(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, onInsert);
    vi.clearAllMocks();
  });

  it('shows nothing when the contact has no abandoned cart', async () => {
    const wrapper = await mountCarts([
      { store: STORE, state: 'ok', carts: [] },
      {
        store: { ...STORE, id: 8 },
        state: 'unavailable',
        error: 'RECOVERY_DISABLED',
        carts: [],
      },
    ]);

    expect(wrapper.find('[data-test-id="commerce-carts"]').exists()).toBe(
      false
    );
  });

  it('shows the cart, its items on request, and how it matched, without contact details', async () => {
    const wrapper = await mountCarts([
      { store: STORE, state: 'ok', carts: [cart()] },
    ]);

    expect(wrapper.text()).toContain('Abandoned carts');
    expect(wrapper.text()).toContain('Zid Store · Zid');
    expect(wrapper.text()).toContain(
      'Matched by this conversation’s verified phone'
    );
    expect(wrapper.find('[data-test-id="commerce-cart-items"]').exists()).toBe(
      false
    );
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'View cart')
      .trigger('click');
    expect(wrapper.find('[data-test-id="commerce-cart-items"]').text()).toBe(
      '2 × Oud'
    );
  });

  it('puts a recovery message into the reply box for the agent to send, never sending it', async () => {
    CommerceAPI.prepareRecovery.mockResolvedValue({
      data: {
        recovery_url: 'https://my-store.zid.store/cart/recover/1',
        first_name: 'Omar',
        total: '120.5',
        currency: 'SAR',
        store: { id: 7, name: 'Zid Store' },
        items_count: 2,
      },
    });
    const wrapper = await mountCarts([
      { store: STORE, state: 'ok', carts: [cart()] },
    ]);

    await wrapper
      .find('[data-test-id="commerce-cart-prepare"]')
      .trigger('click');
    await flushPromises();

    expect(CommerceAPI.prepareRecovery).toHaveBeenCalledWith(3, 7, 'c0ffee01', {
      overrideCooldown: false,
    });
    expect(inserted).toMatch(
      /^Hi Omar, you left 2 items in your cart at Zid Store \(SAR\s120\.50\)\. You can complete your order here: https:\/\/my-store\.zid\.store\/cart\/recover\/1$/
    );
    expect(useAlert).toHaveBeenCalledWith(
      'Recovery message added to the reply box. Review it and send it yourself.'
    );
  });

  it('explains why nothing was prepared outside the reply window', async () => {
    CommerceAPI.prepareRecovery.mockRejectedValue({
      response: { status: 422, data: { error: { code: 'CANNOT_REPLY' } } },
    });
    const wrapper = await mountCarts([
      { store: STORE, state: 'ok', carts: [cart()] },
    ]);

    await wrapper
      .find('[data-test-id="commerce-cart-prepare"]')
      .trigger('click');
    await flushPromises();

    expect(inserted).toBeUndefined();
    expect(
      wrapper.find('[data-test-id="commerce-cart-notice"]').text()
    ).toContain('can’t receive a free-form message now');
  });

  it('waits out the cooldown, which only an administrator can override', async () => {
    const recent = Math.floor(Date.now() / 1000) - 3600;
    const cooling = cart({
      recovery: {
        prepared_at: recent,
        sent_at: recent,
        cooldown_until: recent + 86400,
      },
    });
    const wrapper = await mountCarts([
      { store: STORE, state: 'ok', carts: [cooling] },
    ]);

    expect(wrapper.find('[data-test-id="commerce-cart-sent"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-test-id="commerce-cart-cooldown"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-test-id="commerce-cart-prepare"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-test-id="commerce-cart-override"]').exists()
    ).toBe(false);

    mockIsAdmin.value = true;
    const adminView = await mountCarts([
      { store: STORE, state: 'ok', carts: [cooling] },
    ]);
    expect(
      adminView.find('[data-test-id="commerce-cart-override"]').exists()
    ).toBe(true);
  });
});
