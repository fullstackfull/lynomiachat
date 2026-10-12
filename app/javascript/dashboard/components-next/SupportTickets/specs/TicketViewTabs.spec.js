import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TicketViewTabs from '../TicketViewTabs.vue';

withFullI18n();

const mountTabs = (props = {}) =>
  mount(TicketViewTabs, {
    props: { view: 'all', counts: {}, ...props },
  });

describe('TicketViewTabs', () => {
  it('offers the six saved views', () => {
    const labels = mountTabs()
      .findAll('button')
      .map(button => button.text());

    expect(labels).toEqual([
      'All',
      'My cases',
      'Unassigned',
      'Overdue',
      'Resolved',
      'Closed',
    ]);
  });

  it('labels each tab with the figure the list response already carries', () => {
    const wrapper = mountTabs({
      counts: {
        all: 12,
        mine: 3,
        unassigned: 1,
        overdue: 2,
        resolved: 40,
        closed: 7,
      },
    });
    const labels = wrapper.findAll('button').map(button => button.text());

    expect(labels).toEqual([
      'All (12)',
      'My cases (3)',
      'Unassigned (1)',
      'Overdue (2)',
      'Resolved (40)',
      'Closed (7)',
    ]);
  });

  it('shows no number for a view with nothing in it', () => {
    const wrapper = mountTabs({ counts: { all: 5, overdue: 0 } });
    const labels = wrapper.findAll('button').map(button => button.text());

    expect(labels[0]).toBe('All (5)');
    expect(labels[3]).toBe('Overdue');
  });

  it('marks the view the URL names as the active one', () => {
    const wrapper = mountTabs({ view: 'overdue' });
    const active = wrapper
      .findAll('button')
      .filter(button => button.classes('text-n-blue-11'));

    expect(active).toHaveLength(1);
    expect(active[0].text()).toBe('Overdue');
  });

  it('falls back to the first view when the URL names one it does not have', () => {
    const wrapper = mountTabs({ view: 'nonsense' });
    const active = wrapper
      .findAll('button')
      .filter(button => button.classes('text-n-blue-11'));

    expect(active[0].text()).toBe('All');
  });

  it('emits the key of the view that was clicked', async () => {
    const wrapper = mountTabs();

    await wrapper.findAll('button')[1].trigger('click');

    expect(wrapper.emitted('change')).toEqual([['mine']]);
  });
});
