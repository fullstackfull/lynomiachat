import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TicketCompactList from '../TicketCompactList.vue';

withFullI18n();

const NOW = Math.floor(Date.now() / 1000);

const ticket = (overrides = {}) => ({
  id: 1,
  reference: 'TCK-000001',
  title: 'Refund never reached the customer',
  status: 'open',
  priority: 'urgent',
  last_activity_at: NOW - 3600,
  sla: {
    applied: true,
    paused: false,
    breached: true,
    resolution_due_at: NOW - 60,
  },
  ...overrides,
});

const mountList = (props = {}) =>
  mount(TicketCompactList, {
    props: { tickets: [ticket()], hasLoadedOnce: true, ...props },
    global: { stubs: { RouterLink: { template: '<a><slot /></a>' } } },
  });

describe('TicketCompactList', () => {
  it('renders one row per case, with its reference, subject and three readings', () => {
    const wrapper = mountList();

    expect(wrapper.findAll('li')).toHaveLength(1);
    expect(wrapper.text()).toContain('TCK-000001');
    expect(wrapper.text()).toContain('Refund never reached the customer');
    expect(wrapper.text()).toContain('Open');
    expect(wrapper.text()).toContain('Urgent');
    expect(wrapper.text()).toContain('Target missed');
  });

  it('shows a spinner only on the first load', () => {
    const first = mountList({
      tickets: [],
      isLoading: true,
      hasLoadedOnce: false,
    });
    expect(first.findComponent({ name: 'Spinner' }).exists()).toBe(true);

    const refresh = mountList({ isLoading: true });
    expect(refresh.findComponent({ name: 'Spinner' }).exists()).toBe(false);
    expect(refresh.findAll('li')).toHaveLength(1);
  });

  it('shows the empty message it was given', () => {
    const wrapper = mountList({
      tickets: [],
      isEmpty: true,
      emptyMessage: 'No case is linked to this conversation.',
    });

    expect(wrapper.text()).toContain('No case is linked to this conversation.');
    expect(wrapper.find('ul').exists()).toBe(false);
  });

  it('shows an error instead of the list, never alongside it', () => {
    const wrapper = mountList({
      errorMessage: 'These cases could not be loaded.',
    });

    expect(wrapper.text()).toContain('These cases could not be loaded.');
    expect(wrapper.find('ul').exists()).toBe(false);
  });
});
