import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/commerce.json';
import CommerceAPI from 'dashboard/api/commerce';
import SallaConnectDialog from '../SallaConnectDialog.vue';

// Commerce copy names the product through an `{installationName}` placeholder, which the components read from
// globalConfig. A deliberately unbranded name here proves the substitution happens rather than restating
// whatever this installation is currently called.
const brandingStore = createStore({
  getters: {
    'globalConfig/get': () => ({ installationName: 'Acme Desk' }),
    'globalConfig/isACustomBrandedInstance': () => true,
  },
});

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }));
vi.mock('dashboard/api/commerce', () => ({
  default: { createSallaConnection: vi.fn(), getSallaConnection: vi.fn() },
}));

const DialogStub = {
  props: ['title', 'description'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><h3>{{ title }}</h3><p>{{ description }}</p><slot /></div>',
};

const connection = {
  code: 'ABCD-EFGH-JKLM-NPQR',
  expires_at: '2026-09-30T13:00:00Z',
  install_url: 'https://s.salla.sa/apps/install/1234567890',
};

const mountDialog = () =>
  mount(SallaConnectDialog, {
    props: { show: true },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        brandingStore,
      ],
      stubs: { Dialog: DialogStub },
    },
  });

const createCode = async wrapper => {
  await wrapper.find('[data-test-id="salla-create-code"]').trigger('click');
  await flushPromises();
};

const statusText = wrapper =>
  wrapper.find('[data-test-id="salla-connection-status"]').text();

describe('SallaConnectDialog', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    CommerceAPI.createSallaConnection.mockResolvedValue({ data: connection });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it('explains the steps and asks for nothing secret', () => {
    const wrapper = mountDialog();

    expect(wrapper.text()).toContain('Create a one-time connection code.');
    expect(wrapper.text()).toContain('Install the Acme Desk app in Salla.');
    expect(wrapper.find('input').exists()).toBe(false);
  });

  it('shows the one-time code and the official install link', async () => {
    const wrapper = mountDialog();
    await createCode(wrapper);

    expect(wrapper.find('[data-test-id="salla-connection-code"]').text()).toBe(
      'ABCD-EFGH-JKLM-NPQR'
    );
    const link = wrapper.find('[data-test-id="salla-install-link"]');
    expect(link.attributes('href')).toBe(connection.install_url);
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(statusText(wrapper)).toBe('Waiting for the code from Salla…');
  });

  it('follows the connection until Salla connects the store', async () => {
    CommerceAPI.getSallaConnection
      .mockResolvedValueOnce({ data: { status: 'claimed' } })
      .mockResolvedValueOnce({ data: { status: 'connected', store_id: 7 } });
    const wrapper = mountDialog();
    await createCode(wrapper);

    await vi.advanceTimersByTimeAsync(5000);
    expect(statusText(wrapper)).toBe(
      'Code received. Waiting for Salla to authorize the app…'
    );

    await vi.advanceTimersByTimeAsync(5000);
    expect(statusText(wrapper)).toBe('Your Salla store is connected.');
    expect(wrapper.emitted('connected')).toHaveLength(1);

    await vi.advanceTimersByTimeAsync(15000);
    expect(CommerceAPI.getSallaConnection).toHaveBeenCalledTimes(2);
  });

  it('stops and explains when the store belongs to another account', async () => {
    CommerceAPI.getSallaConnection.mockResolvedValue({
      data: { status: 'conflict' },
    });
    const wrapper = mountDialog();
    await createCode(wrapper);

    await vi.advanceTimersByTimeAsync(10000);

    expect(statusText(wrapper)).toContain(
      'connected to another Acme Desk account'
    );
    expect(CommerceAPI.getSallaConnection).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('connected')).toBeUndefined();
  });

  it('offers a new code when the code expired', async () => {
    CommerceAPI.getSallaConnection.mockResolvedValue({
      data: { status: 'expired' },
    });
    const wrapper = mountDialog();
    await createCode(wrapper);
    await vi.advanceTimersByTimeAsync(5000);

    expect(statusText(wrapper)).toBe('This code expired. Create a new one.');
    expect(wrapper.find('[data-test-id="salla-create-code"]').text()).toContain(
      'Create a new code'
    );
  });

  it('shows why a code cannot be created', async () => {
    CommerceAPI.createSallaConnection.mockRejectedValue({
      response: { data: { error: { code: 'PROVIDER_DISABLED' } } },
    });
    const wrapper = mountDialog();
    await createCode(wrapper);

    expect(wrapper.find('[data-test-id="salla-connection-error"]').text()).toBe(
      'This store platform is turned off on this installation.'
    );
  });

  it('does not link an install URL that is not https', async () => {
    CommerceAPI.createSallaConnection.mockResolvedValue({
      data: { ...connection, install_url: 'http://s.salla.sa/apps/install/1' },
    });
    const wrapper = mountDialog();
    await createCode(wrapper);

    expect(wrapper.find('[data-test-id="salla-install-link"]').exists()).toBe(
      false
    );
  });

  it('forgets the code and stops polling when closed', async () => {
    CommerceAPI.getSallaConnection.mockResolvedValue({
      data: { status: 'waiting' },
    });
    const wrapper = mountDialog();
    await createCode(wrapper);

    await wrapper.setProps({ show: false });
    await vi.advanceTimersByTimeAsync(20000);

    expect(
      wrapper.find('[data-test-id="salla-connection-code"]').exists()
    ).toBe(false);
    expect(CommerceAPI.getSallaConnection).not.toHaveBeenCalled();
  });
});
