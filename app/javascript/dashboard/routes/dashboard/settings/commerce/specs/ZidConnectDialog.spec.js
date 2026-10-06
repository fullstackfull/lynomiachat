import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/commerce.json';
import CommerceAPI from 'dashboard/api/commerce';
import ZidConnectDialog from '../ZidConnectDialog.vue';

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
  default: { createZidConnection: vi.fn() },
}));

const DialogStub = {
  props: ['title', 'description'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><h3>{{ title }}</h3><p>{{ description }}</p><slot /></div>',
};

const mountDialog = () =>
  mount(ZidConnectDialog, {
    props: { show: true },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        brandingStore,
      ],
      stubs: { Dialog: DialogStub },
    },
  });

describe('ZidConnectDialog', () => {
  const assign = vi.fn();

  beforeEach(() => {
    vi.stubGlobal('location', { ...window.location, assign });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  it('explains the authorization and asks for nothing secret', () => {
    const wrapper = mountDialog();

    expect(wrapper.text()).toContain('Connect with Zid');
    expect(wrapper.text()).toContain(
      'You never enter or see a Zid token here.'
    );
    expect(wrapper.find('input').exists()).toBe(false);
  });

  it("sends the browser to Zid's authorization page", async () => {
    const url =
      'https://oauth.zid.sa/oauth/authorize?client_id=4821&response_type=code&state=signed';
    CommerceAPI.createZidConnection.mockResolvedValue({
      data: { authorize_url: url },
    });
    const wrapper = mountDialog();

    await wrapper.find('[data-test-id="zid-connect"]').trigger('click');
    await flushPromises();

    expect(assign).toHaveBeenCalledWith(url);
  });

  it('never follows a link that is not https', async () => {
    CommerceAPI.createZidConnection.mockResolvedValue({
      data: { authorize_url: 'http://oauth.zid.sa/oauth/authorize' },
    });
    const wrapper = mountDialog();

    await wrapper.find('[data-test-id="zid-connect"]').trigger('click');
    await flushPromises();

    expect(assign).not.toHaveBeenCalled();
  });

  it('shows why it cannot start, such as Zid being switched off', async () => {
    CommerceAPI.createZidConnection.mockRejectedValue({
      response: { data: { error: { code: 'PROVIDER_DISABLED' } } },
    });
    const wrapper = mountDialog();

    await wrapper.find('[data-test-id="zid-connect"]').trigger('click');
    await flushPromises();

    expect(
      wrapper.find('[data-test-id="zid-connection-error"]').text()
    ).toContain('turned off on this installation');
    expect(assign).not.toHaveBeenCalled();
  });
});
