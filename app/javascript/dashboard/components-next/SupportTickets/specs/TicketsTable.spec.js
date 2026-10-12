import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TicketsTable from '../TicketsTable.vue';

withFullI18n();

const NOW = 1_760_000_000;

const ticket = (overrides = {}) => ({
  id: 1,
  reference: 'TCK-000001',
  title: 'Inbound IMAP has been failing since Tuesday',
  status: 'in_progress',
  priority: 'high',
  contact_id: 5,
  contact_name: 'Nadia Al-Sabah',
  assignee_id: 3,
  team_id: 2,
  last_activity_at: NOW,
  sla: {
    applied: true,
    paused: false,
    breached: false,
    resolution_due_at: NOW + 7200,
  },
  ...overrides,
});

const mountTable = (props = {}) =>
  mount(TicketsTable, {
    props: {
      tickets: [ticket()],
      agents: [{ id: 3, name: 'Maya Chen' }],
      teams: [{ id: 2, name: 'Platform' }],
      ...props,
    },
    global: {
      stubs: { RouterLink: { template: '<a><slot /></a>' } },
    },
  });

describe('TicketsTable', () => {
  it('names every column the workspace is read by', () => {
    const headers = mountTable()
      .findAll('th')
      .map(header => header.text());

    expect(headers).toEqual([
      'Reference',
      'Subject',
      'Contact',
      'Status',
      'Priority',
      'Owner',
      'SLA',
      'Last activity',
    ]);
  });

  it('renders one row per case, with its reference, subject and contact', () => {
    const wrapper = mountTable();

    expect(wrapper.findAll('tbody tr')).toHaveLength(1);
    expect(wrapper.text()).toContain('TCK-000001');
    expect(wrapper.text()).toContain(
      'Inbound IMAP has been failing since Tuesday'
    );
    expect(wrapper.text()).toContain('Nadia Al-Sabah');
  });

  it('translates the status and priority rather than showing the enum value', () => {
    const wrapper = mountTable();

    expect(wrapper.text()).toContain('In progress');
    expect(wrapper.text()).toContain('High');
    expect(wrapper.text()).not.toContain('in_progress');
  });

  it('shows the assignee as the owner, and falls back to the team', () => {
    expect(mountTable().text()).toContain('Maya Chen');
    expect(
      mountTable({ tickets: [ticket({ assignee_id: null })] }).text()
    ).toContain('Platform');
    expect(
      mountTable({
        tickets: [ticket({ assignee_id: null, team_id: null })],
      }).text()
    ).toContain('Nobody');
  });

  it('shows a dash for a case with no contact linked to it', () => {
    const wrapper = mountTable({
      tickets: [ticket({ contact_id: null, contact_name: null })],
    });

    expect(wrapper.text()).toContain('—');
  });

  it('draws skeleton rows while loading instead of an empty table', () => {
    const wrapper = mountTable({ tickets: [], loading: true });

    expect(wrapper.find('table').attributes('aria-busy')).toBe('true');
    expect(wrapper.findAll('tbody tr[aria-hidden="true"]')).toHaveLength(8);
    expect(wrapper.text()).toContain('Fetching cases…');
  });

  it('shows the message it was given when there is nothing to list', () => {
    const wrapper = mountTable({
      tickets: [],
      noDataMessage: 'No cases match these filters',
    });

    expect(wrapper.text()).toContain('No cases match these filters');
  });

  it('keeps the headings in the empty state, so the columns still say what they were', () => {
    const wrapper = mountTable({ tickets: [], noDataMessage: 'Nothing here' });

    expect(wrapper.findAll('th')).toHaveLength(8);
  });

  it('draws the arrow from the sort key the URL carries', () => {
    const ascending = mountTable({ sort: 'last_activity_at_asc' });
    const headers = ascending.findAll('th');

    expect(headers[7].attributes('aria-sort')).toBe('ascending');
    expect(headers[4].attributes('aria-sort')).toBeUndefined();
  });

  it('defaults to newest activity first when the URL names no sort', () => {
    const headers = mountTable().findAll('th');

    expect(headers[7].attributes('aria-sort')).toBe('descending');
  });

  it('emits the server sort key for the heading that was clicked', async () => {
    const wrapper = mountTable({ sort: 'last_activity_at' });

    await wrapper.findAll('th')[7].find('button').trigger('click');

    expect(wrapper.emitted('sort')).toEqual([['last_activity_at_asc']]);
  });

  it('re-asks the same question for a column the server orders one way only', async () => {
    const wrapper = mountTable({ sort: 'priority' });

    await wrapper.findAll('th')[4].find('button').trigger('click');

    expect(wrapper.emitted('sort')).toEqual([['priority']]);
  });

  it('offers no sort on the columns the server cannot order by', () => {
    const headers = mountTable().findAll('th');

    [0, 1, 2, 3, 5].forEach(index => {
      expect(headers[index].find('button').exists()).toBe(false);
    });
  });
});
