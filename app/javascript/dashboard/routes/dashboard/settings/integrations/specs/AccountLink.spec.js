import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/accountLink.json';
import AccountLinkAPI from 'dashboard/api/accountLink';
import AccountGrantsAPI from 'dashboard/api/accountGrants';
import AccountLink from '../AccountLink.vue';

// The copy names the product through an `{installationName}` placeholder read from globalConfig. A deliberately
// unbranded name here proves the substitution happens rather than restating whatever this installation is called.
const brandingStore = createStore({
  getters: {
    'globalConfig/get': () => ({ installationName: 'Acme Desk' }),
    'globalConfig/isACustomBrandedInstance': () => true,
  },
});

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('shared/helpers/clipboard', () => ({ copyTextToClipboard: vi.fn() }));
vi.mock('dashboard/api/accountLink', () => ({
  default: { createCode: vi.fn(), getStatus: vi.fn() },
}));
vi.mock('dashboard/api/accountGrants', () => ({
  default: { get: vi.fn(), revoke: vi.fn() },
}));

const LayoutStub = {
  template: '<div><slot name="header" /><slot name="body" /></div>',
};
// The dialog teleports to body and manages a native <dialog>, neither of which exists usefully
// here. Stubbed down to the two things the page actually drives: open(), and the confirm event.
const DialogStub = {
  props: ['title', 'description'],
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template:
    '<div data-test-id="revoke-dialog">{{ description }}<button data-test-id="revoke-confirm" @click="$emit(\'confirm\')" /></div>',
};
const HeaderStub = {
  props: ['title', 'description'],
  template: '<div><h3>{{ title }}</h3><p>{{ description }}</p></div>',
};

const mountPage = async () => {
  const wrapper = mount(AccountLink, {
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        brandingStore,
      ],
      stubs: {
        SettingsLayout: LayoutStub,
        BaseSettingsHeader: HeaderStub,
        Dialog: DialogStub,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

// The Select renders a wrapper div around the native control, and the test id lands on the
// wrapper, so the option is set on the <select> inside it.
const choose = async (wrapper, id) => {
  await wrapper.find('[data-test-id="account-link-app"] select').setValue(id);
};

const generate = async wrapper => {
  await wrapper.find('[data-test-id="account-link-create"]').trigger('click');
  await flushPromises();
};

const codeText = wrapper =>
  wrapper.find('[data-test-id="account-link-code"]').text();
const statusText = wrapper =>
  wrapper.find('[data-test-id="account-link-status"]').text();

beforeEach(() => {
  vi.useFakeTimers();
  AccountLinkAPI.getStatus.mockResolvedValue({ data: { status: 'none' } });
  AccountLinkAPI.createCode.mockResolvedValue({
    data: {
      code: 'ABCD-2345-EFGH-6789',
      expires_at: '2026-09-30T13:00:00Z',
      platform_app: { id: 7, name: 'Store Syria' },
    },
  });
  // One app only, so the page pre-selects it and the existing examples below stay about
  // what they were about. The multi-app cases script their own list.
  AccountGrantsAPI.get.mockResolvedValue({
    data: { grants: [], platform_apps: [{ id: 7, name: 'Store Syria' }] },
  });
  AccountGrantsAPI.revoke.mockResolvedValue({ data: { revoked: true } });
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.clearAllMocks();
});

describe('AccountLink', () => {
  it('shows the code once it is generated', async () => {
    const wrapper = await mountPage();

    expect(wrapper.find('[data-test-id="account-link-code"]').exists()).toBe(
      false
    );

    await generate(wrapper);

    expect(codeText(wrapper)).toBe('ABCD-2345-EFGH-6789');
    expect(wrapper.text()).toContain('shown only once');
  });

  it('renders the code left to right so it does not mirror', async () => {
    const wrapper = await mountPage();
    await generate(wrapper);

    expect(
      wrapper.find('[data-test-id="account-link-code"]').attributes('dir')
    ).toBe('ltr');
  });

  it('substitutes the installation name into the description', async () => {
    const wrapper = await mountPage();

    expect(wrapper.text()).toContain('Acme Desk');
  });

  it('polls while the code is unused and stops once it is connected', async () => {
    const wrapper = await mountPage();
    await generate(wrapper);

    AccountLinkAPI.getStatus.mockResolvedValue({
      data: { status: 'waiting', intended_app: 'Store Syria' },
    });
    await vi.advanceTimersByTimeAsync(5000);
    // Named while waiting too, not only once connected: after a reload the code itself is gone
    // from the page, and who it is addressed to is what tells the merchant they minted the right one.
    expect(statusText(wrapper)).toContain('Waiting for Store Syria');

    AccountLinkAPI.getStatus.mockResolvedValue({
      data: { status: 'connected', connected_app: 'Store Syria' },
    });
    await vi.advanceTimersByTimeAsync(5000);
    // Named, so a code pasted into the wrong integration is something the merchant can see.
    expect(statusText(wrapper)).toContain('Connected to Store Syria');

    const callsWhenSettled = AccountLinkAPI.getStatus.mock.calls.length;
    await vi.advanceTimersByTimeAsync(20000);
    // A settled status must stop the timer; polling a connected workspace forever is a
    // request every five seconds for as long as the tab is open.
    expect(AccountLinkAPI.getStatus.mock.calls.length).toBe(callsWhenSettled);
  });

  it('resumes polling for a merchant who reloads mid-connection', async () => {
    AccountLinkAPI.getStatus.mockResolvedValue({ data: { status: 'waiting' } });

    const wrapper = await mountPage();
    expect(statusText(wrapper)).toContain('Waiting');

    const onLoad = AccountLinkAPI.getStatus.mock.calls.length;
    await vi.advanceTimersByTimeAsync(5000);
    expect(AccountLinkAPI.getStatus.mock.calls.length).toBeGreaterThan(onLoad);
  });

  it('reports a failure without claiming a code was issued', async () => {
    AccountLinkAPI.createCode.mockRejectedValue(new Error('boom'));

    const wrapper = await mountPage();
    await generate(wrapper);

    expect(wrapper.find('[data-test-id="account-link-error"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-test-id="account-link-code"]').exists()).toBe(
      false
    );
  });

  // ---------------------------------------------------------------- audience

  it('mints the code for the integration the merchant chose', async () => {
    AccountGrantsAPI.get.mockResolvedValue({
      data: {
        grants: [],
        platform_apps: [
          { id: 7, name: 'Store Syria' },
          { id: 9, name: 'Another Platform' },
        ],
      },
    });

    const wrapper = await mountPage();
    await choose(wrapper, '9');
    await generate(wrapper);

    expect(AccountLinkAPI.createCode).toHaveBeenCalledWith(9);
  });

  /**
   * A code with no audience is a bearer token for whoever presents it first. With more than
   * one integration on the installation the page must not choose for the merchant, and must
   * not send the request at all until they have.
   */
  it('refuses to mint a code before an integration is chosen', async () => {
    AccountGrantsAPI.get.mockResolvedValue({
      data: {
        grants: [],
        platform_apps: [
          { id: 7, name: 'Store Syria' },
          { id: 9, name: 'Another Platform' },
        ],
      },
    });

    const wrapper = await mountPage();
    await generate(wrapper);

    expect(AccountLinkAPI.createCode).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-test-id="account-link-error"]').text()
    ).toContain('Choose the platform');
  });

  it('says on the code itself which integration may use it', async () => {
    const wrapper = await mountPage();
    await generate(wrapper);

    expect(
      wrapper.find('[data-test-id="account-link-audience"]').text()
    ).toContain('Only Store Syria can use this code');
  });

  // ---------------------------------------------------------------- grants

  it('lists what holds access and who it signs in as', async () => {
    AccountGrantsAPI.get.mockResolvedValue({
      data: {
        platform_apps: [{ id: 7, name: 'Store Syria' }],
        grants: [
          {
            platform_app_id: 7,
            platform_app_name: 'Store Syria',
            granted_at: '2026-09-01T10:00:00Z',
            signs_in_as: [{ id: 3, name: 'Hala Merchant' }],
          },
        ],
      },
    });

    const wrapper = await mountPage();

    const list = wrapper.find('[data-test-id="account-link-grants"]');
    expect(list.text()).toContain('Store Syria');
    expect(list.text()).toContain('Hala Merchant');
  });

  it('says plainly when nothing holds access', async () => {
    const wrapper = await mountPage();

    expect(
      wrapper.find('[data-test-id="account-link-grants-empty"]').exists()
    ).toBe(true);
  });

  /**
   * THE POINT OF THE WHOLE SECTION. Until this existed a grant could only be withdrawn by the
   * integration holding it -- the party least likely to volunteer.
   */
  it('lets the merchant disconnect an integration, after confirming', async () => {
    AccountGrantsAPI.get.mockResolvedValue({
      data: {
        platform_apps: [{ id: 7, name: 'Store Syria' }],
        grants: [
          {
            platform_app_id: 7,
            platform_app_name: 'Store Syria',
            granted_at: '2026-09-01T10:00:00Z',
            signs_in_as: [],
          },
        ],
      },
    });

    const wrapper = await mountPage();

    await wrapper
      .find('[data-test-id="account-link-revoke-7"]')
      .trigger('click');
    await flushPromises();

    // Nothing has been revoked yet -- the button opens the confirmation, it does not act.
    expect(AccountGrantsAPI.revoke).not.toHaveBeenCalled();
    expect(wrapper.find('[data-test-id="revoke-dialog"]').text()).toContain(
      'Disconnect Store Syria?'
    );

    await wrapper.find('[data-test-id="revoke-confirm"]').trigger('click');
    await flushPromises();

    expect(AccountGrantsAPI.revoke).toHaveBeenCalledWith(7);
  });

  it('reports a failed disconnect instead of claiming it worked', async () => {
    AccountGrantsAPI.get.mockResolvedValue({
      data: {
        platform_apps: [{ id: 7, name: 'Store Syria' }],
        grants: [
          {
            platform_app_id: 7,
            platform_app_name: 'Store Syria',
            granted_at: '2026-09-01T10:00:00Z',
            signs_in_as: [],
          },
        ],
      },
    });
    AccountGrantsAPI.revoke.mockRejectedValue(new Error('boom'));

    const wrapper = await mountPage();
    await wrapper
      .find('[data-test-id="account-link-revoke-7"]')
      .trigger('click');
    await flushPromises();
    await wrapper.find('[data-test-id="revoke-confirm"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-test-id="account-link-error"]').exists()).toBe(
      true
    );
    // Still listed, because it still holds access.
    expect(
      wrapper.find('[data-test-id="account-link-grants"]').text()
    ).toContain('Store Syria');
  });

  it('stops polling when it is unmounted', async () => {
    const wrapper = await mountPage();
    await generate(wrapper);

    AccountLinkAPI.getStatus.mockResolvedValue({ data: { status: 'waiting' } });
    await vi.advanceTimersByTimeAsync(5000);

    const beforeUnmount = AccountLinkAPI.getStatus.mock.calls.length;
    wrapper.unmount();
    await vi.advanceTimersByTimeAsync(20000);

    expect(AccountLinkAPI.getStatus.mock.calls.length).toBe(beforeUnmount);
  });
});
