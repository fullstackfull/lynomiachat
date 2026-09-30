import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/commerce.json';
import CommerceAPI from 'dashboard/api/commerce';
import ShopifyConnectDialog from '../ShopifyConnectDialog.vue';

vi.mock('dashboard/api/commerce', () => ({
  default: { createShopifyConnection: vi.fn() },
}));

const DialogStub = {
  props: ['title', 'description'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><h3>{{ title }}</h3><p>{{ description }}</p><slot /></div>',
};

const AUTHORIZE_URL =
  'https://lynomia-demo.myshopify.com/admin/oauth/authorize?client_id=c&scope=read_customers%2Cread_orders&state=signed';

const mountDialog = async (props = {}) => {
  const wrapper = mount(ShopifyConnectDialog, {
    props: { show: false, ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: { Dialog: DialogStub },
    },
  });
  await wrapper.setProps({ show: true });
  return wrapper;
};

const connectWith = async (wrapper, shop) => {
  await wrapper.find('input').setValue(shop);
  await wrapper.find('[data-test-id="shopify-connect"]').trigger('click');
  await flushPromises();
};

describe('ShopifyConnectDialog', () => {
  const assign = vi.fn();

  beforeEach(() => {
    vi.stubGlobal('location', { ...window.location, assign });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  it('asks only for the myshopify.com domain, never for a token or key', async () => {
    const wrapper = await mountDialog();

    expect(wrapper.text()).toContain('Connect with Shopify');
    expect(wrapper.text()).toContain(
      'You never enter or see a Shopify token here.'
    );
    expect(wrapper.findAll('input')).toHaveLength(1);
    expect(wrapper.find('input[type="password"]').exists()).toBe(false);
    expect(wrapper.find('input').attributes('placeholder')).toBe(
      'your-store.myshopify.com'
    );
  });

  it("sends the domain and takes the browser to the shop's authorization page", async () => {
    CommerceAPI.createShopifyConnection.mockResolvedValue({
      data: { authorize_url: AUTHORIZE_URL },
    });
    const wrapper = await mountDialog();

    await connectWith(wrapper, ' lynomia-demo.myshopify.com ');

    expect(CommerceAPI.createShopifyConnection).toHaveBeenCalledWith(
      'lynomia-demo.myshopify.com'
    );
    expect(assign).toHaveBeenCalledWith(AUTHORIZE_URL);
  });

  it('starts with the store domain when reconnecting', async () => {
    CommerceAPI.createShopifyConnection.mockResolvedValue({
      data: { authorize_url: AUTHORIZE_URL },
    });
    const wrapper = await mountDialog({ shop: 'lynomia-demo.myshopify.com' });

    expect(wrapper.find('input').element.value).toBe(
      'lynomia-demo.myshopify.com'
    );
    await wrapper.find('[data-test-id="shopify-connect"]').trigger('click');
    await flushPromises();

    expect(CommerceAPI.createShopifyConnection).toHaveBeenCalledWith(
      'lynomia-demo.myshopify.com'
    );
  });

  it('never follows a link that is not https', async () => {
    CommerceAPI.createShopifyConnection.mockResolvedValue({
      data: { authorize_url: 'http://lynomia-demo.myshopify.com/admin' },
    });
    const wrapper = await mountDialog();

    await connectWith(wrapper, 'lynomia-demo.myshopify.com');

    expect(assign).not.toHaveBeenCalled();
  });

  it('explains a domain that is not a myshopify.com domain', async () => {
    CommerceAPI.createShopifyConnection.mockRejectedValue({
      response: {
        data: {
          error: { code: 'INVALID_STORE_URL', reason: 'shopify_domain' },
        },
      },
    });
    const wrapper = await mountDialog();

    await connectWith(wrapper, 'https://evil.example.com');

    expect(
      wrapper.find('[data-test-id="shopify-connection-error"]').text()
    ).toBe(
      "Enter the store's myshopify.com domain, like your-store.myshopify.com."
    );
    expect(assign).not.toHaveBeenCalled();
  });

  it('explains a store already shown through the Shopify integration', async () => {
    CommerceAPI.createShopifyConnection.mockRejectedValue({
      response: {
        data: {
          error: {
            code: 'STORE_ALREADY_CONNECTED',
            reason: 'legacy_shopify_integration',
          },
        },
      },
    });
    const wrapper = await mountDialog();

    await connectWith(wrapper, 'lynomia-demo.myshopify.com');

    expect(
      wrapper.find('[data-test-id="shopify-connection-error"]').text()
    ).toContain("already connected through this account's Shopify integration");
  });
});
