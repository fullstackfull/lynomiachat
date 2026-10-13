import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/accountLink.json';
import AccountLinkAPI from 'dashboard/api/accountLink';
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

const LayoutStub = {
  template: '<div><slot name="header" /><slot name="body" /></div>',
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
      stubs: { SettingsLayout: LayoutStub, BaseSettingsHeader: HeaderStub },
    },
  });
  await flushPromises();
  return wrapper;
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
    data: { code: 'ABCD-2345-EFGH-6789', expires_at: '2026-09-30T13:00:00Z' },
  });
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

    AccountLinkAPI.getStatus.mockResolvedValue({ data: { status: 'waiting' } });
    await vi.advanceTimersByTimeAsync(5000);
    expect(statusText(wrapper)).toContain('Waiting');

    AccountLinkAPI.getStatus.mockResolvedValue({
      data: { status: 'connected' },
    });
    await vi.advanceTimersByTimeAsync(5000);
    expect(statusText(wrapper)).toContain('Connected');

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
