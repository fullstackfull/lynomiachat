import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TicketFilters from '../TicketFilters.vue';

withFullI18n();

const AGENTS = [{ id: 3, name: 'Maya Chen' }];
const TEAMS = [{ id: 2, name: 'Platform' }];

// Index-aligned with the bar's own order, after the date-range control.
const MENU = {
  STATUS: 0,
  PRIORITY: 1,
  CATEGORY: 2,
  ASSIGNEE: 3,
  TEAM: 4,
  SLA: 5,
  SORT: 6,
};

const mountFilters = (filters = {}) =>
  mount(TicketFilters, {
    props: {
      filters: { view: 'all', page: 1, ...filters },
      agents: AGENTS,
      teams: TEAMS,
    },
    global: { stubs: { WootDatePicker: true } },
  });

// The bar renders the date button first, then one trigger per dropdown.
const triggers = wrapper => wrapper.findAll('button[aria-haspopup="menu"]');

const openMenu = async (wrapper, index) => {
  await triggers(wrapper)[index].trigger('click');
  return wrapper;
};

const itemsOf = wrapper =>
  wrapper.findAll('button').map(button => button.text());

describe('TicketFilters', () => {
  it('labels every dropdown with what is currently selected', () => {
    const labels = triggers(mountFilters()).map(button => button.text());

    expect(labels).toEqual([
      'Any status',
      'Any priority',
      'Any category',
      'Anyone',
      'Any team',
      'Any SLA state',
      'Newest activity first',
    ]);
  });

  it('reads the selection out of the filters it was given', () => {
    const labels = triggers(
      mountFilters({
        status: 'waiting_on_customer',
        priority: 'urgent',
        category: 'billing',
        assignee_id: 3,
        team_id: 2,
        sla: 'breached',
        sort: 'created_at',
      })
    ).map(button => button.text());

    expect(labels).toEqual([
      'Waiting on customer',
      'Urgent',
      'Billing',
      'Maya Chen',
      'Platform',
      'Target missed',
      'Newest first',
    ]);
  });

  it('offers every status the server knows, plus an entry that clears the filter', async () => {
    const wrapper = await openMenu(mountFilters(), MENU.STATUS);
    const labels = itemsOf(wrapper);

    expect(labels).toContain('Any status');
    expect(labels).toContain('Open');
    expect(labels).toContain('Waiting on us');
    expect(labels).toContain('Closed');
  });

  it('offers the two assignee literals above the account agents', async () => {
    const wrapper = await openMenu(mountFilters(), MENU.ASSIGNEE);
    const labels = itemsOf(wrapper);

    expect(labels).toContain('Assigned to me');
    expect(labels).toContain('Nobody');
    expect(labels).toContain('Maya Chen');
  });

  it('emits only the dimension that changed', async () => {
    const wrapper = await openMenu(mountFilters(), MENU.PRIORITY);
    const urgent = wrapper
      .findAll('button')
      .find(button => button.text() === 'Urgent');

    await urgent.trigger('click');

    expect(wrapper.emitted('update')).toEqual([[{ priority: 'urgent' }]]);
  });

  it('clears a dimension by emitting it with no value', async () => {
    const wrapper = await openMenu(
      mountFilters({ priority: 'urgent' }),
      MENU.PRIORITY
    );
    const any = wrapper
      .findAll('button')
      .find(button => button.text() === 'Any priority');

    await any.trigger('click');

    expect(wrapper.emitted('update')).toEqual([[{ priority: undefined }]]);
  });

  it('treats the default sort as the absence of a sort parameter', async () => {
    const wrapper = await openMenu(
      mountFilters({ sort: 'created_at' }),
      MENU.SORT
    );
    const newest = wrapper
      .findAll('button')
      .find(button => button.text() === 'Newest activity first');

    await newest.trigger('click');

    expect(wrapper.emitted('update')).toEqual([[{ sort: undefined }]]);
  });

  it('emits the team id as a value the server can resolve', async () => {
    const wrapper = await openMenu(mountFilters(), MENU.TEAM);
    const platform = wrapper
      .findAll('button')
      .find(button => button.text() === 'Platform');

    await platform.trigger('click');

    expect(wrapper.emitted('update')).toEqual([[{ team_id: 2 }]]);
  });

  it('closes the open menu after a choice is made', async () => {
    const wrapper = await openMenu(mountFilters(), MENU.SLA);
    expect(wrapper.findComponent({ name: 'DropdownMenu' }).exists()).toBe(true);

    const overdue = wrapper
      .findAll('button')
      .find(button => button.text() === 'Past its resolution time');
    await overdue.trigger('click');

    expect(wrapper.findComponent({ name: 'DropdownMenu' }).exists()).toBe(
      false
    );
  });

  it('shows the date picker once a window is in the URL', () => {
    const withoutWindow = mountFilters();
    expect(
      withoutWindow.findComponent({ name: 'WootDatePicker' }).exists()
    ).toBe(false);
    expect(withoutWindow.text()).toContain('Opened between');

    const withWindow = mountFilters({ since: 100, until: 200 });
    expect(withWindow.findComponent({ name: 'WootDatePicker' }).exists()).toBe(
      true
    );
  });
});
