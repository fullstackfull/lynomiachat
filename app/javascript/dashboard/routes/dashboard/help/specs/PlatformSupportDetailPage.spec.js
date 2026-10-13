import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';

import PlatformSupportDetailPage from '../pages/PlatformSupportDetailPage.vue';
import PlatformSupportAPI from '../platformSupportApi';
import { resetPlatformSupportUnreadState } from '../platformSupportStore';

withFullI18n();

vi.mock('../platformSupportApi', () => ({
  default: {
    getTicket: vi.fn(),
    getMessages: vi.fn(),
    getEvents: vi.fn(),
    createMessage: vi.fn(),
    markViewed: vi.fn(),
    uploadAttachment: vi.fn(),
    attachmentUrl: id =>
      `/api/v1/accounts/1/platform_support/attachments/${id}`,
  },
}));

const push = vi.fn();

vi.mock('vue-router', () => ({
  useRoute: () => ({
    name: 'platform_support_tickets_show',
    params: { accountId: '1', ticketId: '7' },
    query: {},
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

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    docsLink: () => 'https://docs.example.test/contact-lynomia-support',
    brandLink: () => '',
    installationName: ref('Lynomia'),
    replaceInstallationName: text => text,
  }),
}));

const NOW = Math.floor(Date.now() / 1000);

const ticket = (overrides = {}) => ({
  id: 7,
  reference: 'LYN-000007',
  reference_number: 7,
  subject: 'WhatsApp templates are stuck in review',
  description: 'Two templates have been pending since Tuesday.',
  category: 'whatsapp',
  status: 'in_progress',
  priority: 'high',
  reporter_name: 'Dana',
  unread: true,
  message_count: 3,
  attachment_count: 1,
  last_activity_at: NOW - 600,
  last_operator_message_at: NOW - 600,
  resolved_at: null,
  closed_at: null,
  created_at: NOW - 86400,
  updated_at: NOW - 600,
  ...overrides,
});

// The server writes the ticket's description as the FIRST MESSAGE of the thread
// (PlatformSupport::TicketCreation#open_thread), so the API returns it like any other message and the page
// renders no synthetic opening bubble of its own.
const openingMessage = {
  id: 1,
  author_role: 'customer',
  author_name: 'Dana',
  body: 'Two templates have been pending since Tuesday.',
  attachments: [],
  created_at: NOW - 86400 - 1,
};

const customerMessage = {
  id: 2,
  author_role: 'customer',
  author_name: 'Dana',
  body: 'Meta has not answered either submission.',
  attachments: [],
  created_at: NOW - 86400,
};

const operatorMessage = {
  id: 3,
  author_role: 'lynomia',
  author_name: 'Lynomia Support',
  body: 'We have escalated both to Meta.',
  attachments: [
    {
      id: 42,
      filename: 'meta-case.pdf',
      byte_size: 20480,
      content_type: 'application/pdf',
    },
  ],
  created_at: NOW - 600,
};

const createdEvent = {
  id: 10,
  event_type: 'created',
  created_at: NOW - 86400 - 5,
};

const arrange = ({
  ticketPayload = ticket(),
  messages = [openingMessage, customerMessage, operatorMessage],
  events = [createdEvent],
} = {}) => {
  PlatformSupportAPI.getTicket.mockResolvedValue({ data: ticketPayload });
  PlatformSupportAPI.getMessages.mockResolvedValue({
    data: { payload: messages },
  });
  PlatformSupportAPI.getEvents.mockResolvedValue({ data: { payload: events } });
  PlatformSupportAPI.markViewed.mockResolvedValue({ data: {} });
};

const mountPage = () =>
  mount(PlatformSupportDetailPage, {
    global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } },
  });

describe('PlatformSupportDetailPage', () => {
  beforeEach(() => {
    resetPlatformSupportUnreadState();
    push.mockReset();
  });

  it('shows skeletons while the three requests are in flight', async () => {
    PlatformSupportAPI.getTicket.mockReturnValue(new Promise(() => {}));
    PlatformSupportAPI.getMessages.mockReturnValue(new Promise(() => {}));
    PlatformSupportAPI.getEvents.mockReturnValue(new Promise(() => {}));

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[aria-busy="true"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('LYN-000007');
  });

  it('renders the reference, the subject, the three chips and a plain-language state', async () => {
    arrange();
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain('LYN-000007');
    expect(wrapper.text()).toContain('WhatsApp templates are stuck in review');
    expect(wrapper.text()).toContain('In progress');
    expect(wrapper.text()).toContain('WhatsApp');
    expect(wrapper.text()).toContain('High');
    expect(wrapper.text()).toContain('A Lynomia engineer is working on this.');
  });

  it('attributes every operator message to "Lynomia Support" and never to a person', async () => {
    arrange({
      messages: [
        { ...operatorMessage, author_name: 'Faisal al-Otaibi' },
        customerMessage,
      ],
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain('Lynomia Support');
    expect(wrapper.text()).not.toContain('Faisal al-Otaibi');
  });

  it('puts messages and customer-visible events in one list, oldest first', async () => {
    arrange();
    const wrapper = mountPage();
    await flushPromises();

    const body = wrapper.text();
    // The ticket's own description opens the thread, then the customer's reply, then Lynomia's.
    expect(body.indexOf('Ticket opened')).toBeLessThan(
      body.indexOf('Two templates have been pending')
    );
    expect(body.indexOf('Two templates have been pending')).toBeLessThan(
      body.indexOf('Meta has not answered either submission.')
    );
    expect(
      body.indexOf('Meta has not answered either submission.')
    ).toBeLessThan(body.indexOf('We have escalated both to Meta.'));
  });

  it('links an attachment to the authorized download route and never to a blob URL', async () => {
    arrange();
    const wrapper = mountPage();
    await flushPromises();

    const link = wrapper.find('a[download]');
    expect(link.attributes('href')).toBe(
      '/api/v1/accounts/1/platform_support/attachments/42'
    );
    expect(wrapper.html()).not.toContain('rails/active_storage');
  });

  it('shows the new-reply indicator, then stamps the view so the dot clears', async () => {
    arrange();
    const wrapper = mountPage();
    await flushPromises();

    expect(
      wrapper.find('[data-test-id="platform-support-detail-unread"]').exists()
    ).toBe(true);
    expect(PlatformSupportAPI.markViewed).toHaveBeenCalledWith('7');
  });

  it('says that replying reopens a resolved ticket', async () => {
    arrange({ ticketPayload: ticket({ status: 'resolved' }) });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.findComponent({ name: 'ReplyBox' }).exists()).toBe(true);
    expect(wrapper.text()).toContain('Replying reopens it');
  });

  it('offers a new ticket instead of a reply box on a closed ticket', async () => {
    arrange({ ticketPayload: ticket({ status: 'closed' }) });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.findComponent({ name: 'ReplyBox' }).exists()).toBe(false);
    expect(wrapper.text()).toContain('This ticket is closed');
  });

  it('pre-fills the category when the customer opens a new ticket from a closed one', async () => {
    arrange({ ticketPayload: ticket({ status: 'closed' }) });
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.findAll('button').at(-1).trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'platform_support_tickets_new',
      params: { accountId: 1 },
      query: { category: 'whatsapp' },
    });
  });

  it('sends a reply, then re-reads the ticket because a reply can reopen it', async () => {
    arrange({ ticketPayload: ticket({ status: 'resolved' }) });
    PlatformSupportAPI.createMessage.mockResolvedValue({ data: { id: 3 } });

    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('textarea').setValue('Still not fixed.');
    await wrapper.findComponent({ name: 'ReplyBox' }).vm.$emit('send', {
      body: 'Still not fixed.',
      attachment_ids: [],
    });
    await flushPromises();

    expect(PlatformSupportAPI.createMessage).toHaveBeenCalledWith('7', {
      body: 'Still not fixed.',
      attachment_ids: [],
    });
    expect(PlatformSupportAPI.getTicket).toHaveBeenCalledTimes(2);
  });

  it('keeps the typed reply and shows the refusal when the server says the ticket is closed', async () => {
    arrange();
    PlatformSupportAPI.createMessage.mockRejectedValue({
      response: {
        status: 422,
        data: { message: 'This ticket is closed. Open a new one.' },
      },
    });

    const wrapper = mountPage();
    await flushPromises();

    await wrapper.findComponent({ name: 'ReplyBox' }).vm.$emit('send', {
      body: 'Anything?',
      attachment_ids: [],
    });
    await flushPromises();

    expect(wrapper.text()).toContain('This ticket is closed. Open a new one.');
    expect(PlatformSupportAPI.getTicket).toHaveBeenCalledTimes(1);
  });

  it('says a ticket is not visible rather than leaking that it exists', async () => {
    PlatformSupportAPI.getTicket.mockRejectedValue({
      response: { status: 404, data: { error: 'Resource not found' } },
    });
    PlatformSupportAPI.getMessages.mockRejectedValue({
      response: { status: 404 },
    });
    PlatformSupportAPI.getEvents.mockRejectedValue({
      response: { status: 404 },
    });

    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'does not exist, or it is not one you can see'
    );
    expect(PlatformSupportAPI.markViewed).not.toHaveBeenCalled();
  });
});
