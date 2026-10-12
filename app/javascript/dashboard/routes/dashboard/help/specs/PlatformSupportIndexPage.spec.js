import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';

import PlatformSupportIndexPage from '../pages/PlatformSupportIndexPage.vue';
import PlatformSupportAPI from '../platformSupportApi';
import { resetPlatformSupportUnreadState } from '../platformSupportStore';
import { PLATFORM_SUPPORT_PAGE_SIZE } from '../constants';

withFullI18n();

vi.mock('../platformSupportApi', () => ({
  default: {
    getTickets: vi.fn(),
    attachmentUrl: id =>
      `/api/v1/accounts/1/platform_support/attachments/${id}`,
  },
}));

const push = vi.fn();
const routeQuery = ref({});

vi.mock('vue-router', () => ({
  useRoute: () => ({
    name: 'platform_support_tickets_index',
    params: { accountId: '1' },
    get query() {
      return routeQuery.value;
    },
  }),
  useRouter: () => ({ push }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(1),
    accountScopedRoute: (name, params = {}, query = {}) => ({
      name,
      params: { accountId: 1, ...params },
      query,
    }),
  }),
}));

// The branded-installation rule: an installation with no DOCUMENTATION_URL yields '' and the link renders
// nothing at all. Driven from this ref so one example can assert each side of it.
const docsUrl = ref('https://docs.example.test/contact-lynomia-support');

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    docsLink: () => docsUrl.value,
    brandLink: () => '',
    installationName: ref('Lynomia'),
    replaceInstallationName: text => text,
  }),
}));

const NOW = Math.floor(Date.now() / 1000);

const ticket = (overrides = {}) => ({
  id: 1,
  reference: 'LYN-000001',
  reference_number: 1,
  subject: 'Invoices are not arriving',
  category: 'billing',
  status: 'open',
  priority: 'high',
  reporter_name: 'Dana',
  unread: false,
  message_count: 2,
  attachment_count: 0,
  last_activity_at: NOW - 3600,
  created_at: NOW - 7200,
  ...overrides,
});

const listResponse = (payload, meta = {}) => ({
  data: {
    payload,
    meta: {
      current_page: 1,
      total_entries: payload.length,
      per_page: PLATFORM_SUPPORT_PAGE_SIZE,
      counts: { open: payload.length, closed: 0, unread: 0 },
      ...meta,
    },
  },
});

const mountPage = () =>
  mount(PlatformSupportIndexPage, {
    global: {
      stubs: { RouterLink: { template: '<a><slot /></a>' } },
    },
  });

describe('PlatformSupportIndexPage', () => {
  beforeEach(() => {
    resetPlatformSupportUnreadState();
    routeQuery.value = {};
    docsUrl.value = 'https://docs.example.test/contact-lynomia-support';
    push.mockReset();
  });

  it('shows card-shaped skeletons on the first load, not a spinner', async () => {
    let settle;
    PlatformSupportAPI.getTickets.mockReturnValue(
      new Promise(resolve => {
        settle = resolve;
      })
    );

    const wrapper = mountPage();
    await flushPromises();

    expect(
      wrapper.find('[data-test-id="platform-support-list-skeleton"]').exists()
    ).toBe(true);

    settle(listResponse([ticket()]));
    await flushPromises();

    expect(
      wrapper.find('[data-test-id="platform-support-list-skeleton"]').exists()
    ).toBe(false);
  });

  it('groups the list into Open and Closed rather than offering a filter bar', async () => {
    PlatformSupportAPI.getTickets.mockResolvedValue(
      listResponse([
        ticket(),
        ticket({ id: 2, reference: 'LYN-000002', status: 'closed' }),
        ticket({ id: 3, reference: 'LYN-000003', status: 'resolved' }),
      ])
    );

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain('Open');
    expect(wrapper.text()).toContain('Closed');
    expect(wrapper.findAll('li')).toHaveLength(3);
    // Two groupings, not a filter bar: no search box and no status control on this page.
    expect(wrapper.find('input[type="search"]').exists()).toBe(false);
  });

  it('marks a ticket Lynomia has replied to since the customer last looked', async () => {
    PlatformSupportAPI.getTickets.mockResolvedValue(
      listResponse([ticket({ unread: true })])
    );

    const wrapper = mountPage();
    await flushPromises();

    expect(
      wrapper.find('[data-test-id="platform-support-unread-dot"]').exists()
    ).toBe(true);
  });

  it('teaches what the desk is for in the empty state, and what it is not for', async () => {
    PlatformSupportAPI.getTickets.mockResolvedValue(listResponse([]));

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain('No tickets yet');
    expect(wrapper.text()).toContain('billing');
    expect(wrapper.text()).toContain('use Inbox');
  });

  it('shows the server reason on a refusal, and never the list beside it', async () => {
    PlatformSupportAPI.getTickets.mockRejectedValue({
      response: { status: 422, data: { message: 'Unknown filter value' } },
    });

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain('Unknown filter value');
    expect(wrapper.findAll('li')).toHaveLength(0);
  });

  it('falls back to its own sentence when a failure carries no reason', async () => {
    PlatformSupportAPI.getTickets.mockRejectedValue(new Error('network'));

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain('Your tickets could not be loaded');
  });

  it('paginates only past one page', async () => {
    PlatformSupportAPI.getTickets.mockResolvedValue(
      listResponse([ticket()], { total_entries: 3 })
    );

    const onePage = mountPage();
    await flushPromises();
    expect(onePage.findComponent({ name: 'PaginationFooter' }).exists()).toBe(
      false
    );

    PlatformSupportAPI.getTickets.mockResolvedValue(
      listResponse([ticket()], { total_entries: 60 })
    );

    const manyPages = mountPage();
    await flushPromises();
    expect(manyPages.findComponent({ name: 'PaginationFooter' }).exists()).toBe(
      true
    );
  });

  it('re-reads the list when the page in the URL changes, not before', async () => {
    PlatformSupportAPI.getTickets.mockResolvedValue(
      listResponse([ticket()], { total_entries: 60 })
    );

    const wrapper = mountPage();
    await flushPromises();
    expect(PlatformSupportAPI.getTickets).toHaveBeenCalledTimes(1);

    wrapper
      .findComponent({ name: 'PaginationFooter' })
      .vm.$emit('update:currentPage', 2);
    await flushPromises();

    // The footer navigates; it does not fetch. The fetch follows the URL.
    expect(push).toHaveBeenCalledWith({
      name: 'platform_support_tickets_index',
      query: { page: 2 },
    });
    expect(PlatformSupportAPI.getTickets).toHaveBeenCalledTimes(1);

    routeQuery.value = { page: '2' };
    await flushPromises();

    expect(PlatformSupportAPI.getTickets).toHaveBeenLastCalledWith(
      { page: 2, per_page: PLATFORM_SUPPORT_PAGE_SIZE },
      expect.anything()
    );
  });

  it('renders no documentation link at all when the installation has none', async () => {
    PlatformSupportAPI.getTickets.mockResolvedValue(listResponse([ticket()]));

    const withDocs = mountPage();
    await flushPromises();
    expect(withDocs.find('a[href*="contact-lynomia-support"]').exists()).toBe(
      true
    );

    docsUrl.value = '';
    const withoutDocs = mountPage();
    await flushPromises();
    expect(
      withoutDocs.findComponent({ name: 'DocsLink' }).find('a').exists()
    ).toBe(false);
  });
});
