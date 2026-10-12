import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TicketDetailHeader from '../TicketDetailHeader.vue';

withFullI18n();

const NOW = Math.floor(Date.now() / 1000);

const ticket = (overrides = {}) => ({
  reference: 'TCK-000042',
  title: 'Inbound IMAP has been failing since Tuesday',
  status: 'in_progress',
  priority: 'high',
  sla: {
    applied: true,
    paused: false,
    breached: false,
    resolution_due_at: NOW + 7200,
  },
  ...overrides,
});

const mountHeader = (props = {}) =>
  mount(TicketDetailHeader, { props: { ticket: ticket(), ...props } });

const selects = wrapper => wrapper.findAll('select');

const optionsOf = select =>
  select.findAll('option').map(option => option.text());

describe('TicketDetailHeader', () => {
  it('shows the reference, the subject and where the SLA stands', () => {
    const wrapper = mountHeader();

    expect(wrapper.text()).toContain('TCK-000042');
    expect(wrapper.text()).toContain(
      'Inbound IMAP has been failing since Tuesday'
    );
    expect(wrapper.text()).toContain('Due in');
  });

  it('offers an active case every other status', () => {
    const wrapper = mountHeader();

    expect(optionsOf(selects(wrapper)[0])).toEqual([
      'Open',
      'In progress',
      'Waiting on customer',
      'Waiting on us',
      'Resolved',
      'Closed',
    ]);
  });

  it('offers a resolved case only closing or reopening', () => {
    const wrapper = mountHeader({ ticket: ticket({ status: 'resolved' }) });

    expect(optionsOf(selects(wrapper)[0])).toEqual([
      'Open',
      'Resolved',
      'Closed',
    ]);
  });

  it('offers a closed case only reopening', () => {
    const wrapper = mountHeader({ ticket: ticket({ status: 'closed' }) });

    expect(optionsOf(selects(wrapper)[0])).toEqual(['Open', 'Closed']);
  });

  it('shows the status and priority the case currently has', () => {
    const wrapper = mountHeader();

    expect(selects(wrapper)[0].element.value).toBe('in_progress');
    expect(selects(wrapper)[1].element.value).toBe('high');
  });

  it('emits the status the operator picked', async () => {
    const wrapper = mountHeader();

    await selects(wrapper)[0].setValue('resolved');

    expect(wrapper.emitted('update')).toEqual([[{ status: 'resolved' }]]);
  });

  it('emits the priority the operator picked', async () => {
    const wrapper = mountHeader();

    await selects(wrapper)[1].setValue('urgent');

    expect(wrapper.emitted('update')).toEqual([[{ priority: 'urgent' }]]);
  });

  it('locks both controls while a change is in flight', () => {
    const wrapper = mountHeader({ isSaving: true });

    selects(wrapper).forEach(select => {
      expect(select.attributes('disabled')).toBeDefined();
    });
  });

  it('says a case with no policy has none, rather than showing it as on time', () => {
    const wrapper = mountHeader({
      ticket: ticket({ sla: { applied: false } }),
    });

    expect(wrapper.text()).toContain('No SLA policy');
  });
});
