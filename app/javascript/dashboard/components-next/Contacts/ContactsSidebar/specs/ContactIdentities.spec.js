import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ContactAPI from 'dashboard/api/contacts';
import ContactIdentities from '../ContactIdentities.vue';

withFullI18n();

vi.mock('dashboard/api/contacts', () => ({
  default: {
    getIdentities: vi.fn(),
    linkIdentity: vi.fn(),
    unlinkIdentity: vi.fn(),
  },
}));

const alert = vi.fn();
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alert(...args),
}));

const contact = {
  id: 7,
  phone_number: '+96550000001',
  email: 'dana@example.com',
};

const identity = (id, overrides = {}) => ({
  id,
  identity_type: 'phone',
  value: `+9655000000${id}`,
  source: 'agent_linked',
  linked_by_name: 'Sara',
  created_at: '2026-10-09T10:00:00.000Z',
  ...overrides,
});

const mountPanel = async (props = {}) => {
  const wrapper = mount(ContactIdentities, {
    props: { contact, canManage: false, ...props },
  });
  await flushPromises();
  return wrapper;
};

describe('ContactIdentities', () => {
  beforeEach(() => {
    alert.mockReset();
    ContactAPI.getIdentities.mockReset();
    ContactAPI.linkIdentity.mockReset();
    ContactAPI.unlinkIdentity.mockReset();
    ContactAPI.getIdentities.mockResolvedValue({ data: { payload: [] } });
    ContactAPI.linkIdentity.mockResolvedValue({ data: {} });
    ContactAPI.unlinkIdentity.mockResolvedValue({ data: {} });
  });

  it('loads this contact identities on mount', async () => {
    await mountPanel();

    expect(ContactAPI.getIdentities).toHaveBeenCalledWith(7);
  });

  // The two sections come from two sources and saying which is which is the point: a primary field is what an
  // outgoing conversation uses, a linked identity is what an incoming message is matched against.
  it('shows the contact own number and address as primary', async () => {
    const wrapper = await mountPanel();

    const primaries = wrapper.findAll('[data-test-id="primary-identity"]');
    expect(primaries).toHaveLength(2);
    expect(wrapper.text()).toContain('+96550000001');
    expect(wrapper.text()).toContain('dana@example.com');
  });

  it('lists the linked identities separately, with where each came from', async () => {
    ContactAPI.getIdentities.mockResolvedValue({
      data: { payload: [identity(2), identity(3, { source: 'merged' })] },
    });

    const wrapper = await mountPanel();

    expect(wrapper.findAll('[data-test-id="linked-identity"]')).toHaveLength(2);
    expect(wrapper.text()).toContain('From a merge');
  });

  it('says so when the contact has nothing at all', async () => {
    const wrapper = await mountPanel({
      contact: { id: 7, phone_number: '', email: '' },
    });

    expect(wrapper.find('[data-test-id="identities-empty"]').exists()).toBe(
      true
    );
  });

  describe('without permission to manage', () => {
    it('offers no add form and no unlink control', async () => {
      ContactAPI.getIdentities.mockResolvedValue({
        data: { payload: [identity(2)] },
      });

      const wrapper = await mountPanel();

      expect(wrapper.text()).not.toContain('Link another number or address');
      expect(wrapper.findAll('button')).toHaveLength(0);
    });
  });

  describe('with permission to manage', () => {
    it('links the typed value as the chosen type and reloads', async () => {
      const wrapper = await mountPanel({ canManage: true });

      await wrapper.find('input').setValue(' +96560000002 ');
      await wrapper
        .findAll('button')
        .find(button => button.text() === 'Link')
        .trigger('click');
      await flushPromises();

      expect(ContactAPI.linkIdentity).toHaveBeenCalledWith(7, {
        identityType: 'phone',
        value: '+96560000002',
      });
      expect(ContactAPI.getIdentities).toHaveBeenCalledTimes(2);
    });

    // The server refuses a value another contact owns and names it. That refusal is shown, not translated into
    // an offer to merge.
    it('shows the server refusal verbatim', async () => {
      ContactAPI.linkIdentity.mockRejectedValue({
        response: {
          data: {
            error:
              'This already belongs to another contact in this account (contact 42).',
          },
        },
      });

      const wrapper = await mountPanel({ canManage: true });

      await wrapper.find('input').setValue('+96560000002');
      await wrapper
        .findAll('button')
        .find(button => button.text() === 'Link')
        .trigger('click');
      await flushPromises();

      expect(wrapper.text()).toContain('contact 42');
    });

    it('unlinks an identity and reloads', async () => {
      ContactAPI.getIdentities.mockResolvedValue({
        data: { payload: [identity(2)] },
      });

      const wrapper = await mountPanel({ canManage: true });
      await wrapper
        .findAll('button')
        .find(button => button.text() === 'Unlink')
        .trigger('click');
      await flushPromises();

      expect(ContactAPI.unlinkIdentity).toHaveBeenCalledWith(7, 2);
      expect(ContactAPI.getIdentities).toHaveBeenCalledTimes(2);
    });
  });
});
