import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';

import PlatformSupportNewPage from '../pages/PlatformSupportNewPage.vue';
import PlatformSupportAPI from '../platformSupportApi';

withFullI18n();

vi.mock('../platformSupportApi', () => ({
  default: { createTicket: vi.fn() },
}));

const push = vi.fn();

vi.mock('vue-router', () => ({
  useRoute: () => ({
    name: 'platform_support_tickets_new',
    params: {},
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

// The form itself has its own spec; here it is only the thing that emits `submit`, so the page's own
// behaviour — what it sends, and where it sends the customer afterwards — is what is under test.
const FormStub = {
  name: 'NewTicketForm',
  props: ['isSubmitting', 'errorMessage', 'initialCategory'],
  template:
    '<button type="button" @click="$emit(\'submit\', { subject: \'Export is stuck\' })">go</button>',
};

const mountPage = () =>
  mount(PlatformSupportNewPage, {
    global: {
      stubs: {
        NewTicketForm: FormStub,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });

describe('PlatformSupportNewPage', () => {
  beforeEach(() => push.mockReset());

  // THE RECEIPT IS THE TICKET. A customer who has just described a problem must land on the thread, with its
  // reference, and 201 answers in the same `payload` envelope the show endpoint uses — so the id is one level
  // in. Reading it off the response root pushed `ticketId: undefined` and stranded the customer on a route
  // that resolves to nothing.
  it('sends the customer to the ticket it just created', async () => {
    PlatformSupportAPI.createTicket.mockResolvedValue({
      data: { payload: { id: 41, reference: 'LYN-000041' } },
    });

    const wrapper = mountPage();
    await wrapper.find('button[type="button"]').trigger('click');
    await flushPromises();

    expect(PlatformSupportAPI.createTicket).toHaveBeenCalledWith({
      subject: 'Export is stuck',
    });
    expect(push).toHaveBeenCalledWith({
      name: 'platform_support_tickets_show',
      params: { accountId: 1, ticketId: 41 },
      query: {},
    });
  });

  // A 422 carries the reason, which is the message the customer needs.
  it('keeps the customer on the form and shows what the server refused', async () => {
    PlatformSupportAPI.createTicket.mockRejectedValue({
      response: {
        status: 422,
        data: { message: 'A description is required.' },
      },
    });

    const wrapper = mountPage();
    await wrapper.find('button[type="button"]').trigger('click');
    await flushPromises();

    expect(push).not.toHaveBeenCalled();
    expect(wrapper.findComponent(FormStub).props('errorMessage')).toBe(
      'A description is required.'
    );
  });
});
