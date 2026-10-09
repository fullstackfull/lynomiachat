import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TicketHistory from '../TicketHistory.vue';

withFullI18n();

const NOW = Math.floor(Date.now() / 1000);

const event = (overrides = {}) => ({
  id: 1,
  event_type: 'status_changed',
  body: null,
  data: { from: 'open', to: 'in_progress' },
  user_id: 3,
  user_name: 'Maya Chen',
  created_at: NOW - 60,
  ...overrides,
});

const mountHistory = (props = {}) =>
  mount(TicketHistory, {
    props: {
      events: [event()],
      agents: [{ id: 3, name: 'Maya Chen' }],
      teams: [{ id: 2, name: 'Platform' }],
      ...props,
    },
  });

describe('TicketHistory', () => {
  it('renders one entry per event, with who did it', () => {
    const wrapper = mountHistory();

    expect(wrapper.findAll('ul li')).toHaveLength(1);
    expect(wrapper.text()).toContain('Status changed');
    expect(wrapper.text()).toContain('Maya Chen');
  });

  it('reads a status change in the product vocabulary, not the enum values', () => {
    const wrapper = mountHistory();

    expect(wrapper.text()).toContain('Open → In progress');
    expect(wrapper.text()).not.toContain('in_progress');
  });

  it('reads a priority change in its own vocabulary', () => {
    const wrapper = mountHistory({
      events: [
        event({
          event_type: 'priority_changed',
          data: { from: 'low', to: 'urgent' },
        }),
      ],
    });

    expect(wrapper.text()).toContain('Priority changed');
    expect(wrapper.text()).toContain('Low → Urgent');
  });

  it('resolves an assignment to the agent name', () => {
    const wrapper = mountHistory({
      events: [event({ event_type: 'assigned', data: { from: null, to: 3 } })],
    });

    expect(wrapper.text()).toContain('Set to Maya Chen');
  });

  it('resolves a team change to the team name', () => {
    const wrapper = mountHistory({
      events: [
        event({ event_type: 'team_changed', data: { from: 2, to: null } }),
      ],
    });

    expect(wrapper.text()).toContain('Cleared Platform');
  });

  it('shows an agent id verbatim when the agent is no longer in the account', () => {
    const wrapper = mountHistory({
      events: [event({ event_type: 'assigned', data: { from: null, to: 99 } })],
      agents: [],
    });

    expect(wrapper.text()).toContain('Set to 99');
  });

  it('shows a note body and no change line', () => {
    const wrapper = mountHistory({
      events: [
        event({
          event_type: 'note',
          body: 'Chased the vendor, waiting on their ticket.',
          data: {},
        }),
      ],
    });

    expect(wrapper.text()).toContain('Internal note');
    expect(wrapper.text()).toContain(
      'Chased the vendor, waiting on their ticket.'
    );
  });

  it('attributes an event with no user to the system', () => {
    const wrapper = mountHistory({
      events: [
        event({
          event_type: 'sla_resolution_breached',
          user_id: null,
          user_name: null,
          data: { due_at: '2026-10-01T10:00:00.000Z' },
        }),
      ],
    });

    expect(wrapper.text()).toContain('Resolution target missed');
    expect(wrapper.text()).toContain('Lynomia');
  });

  it('carries no change line for an event whose data is a timestamp', () => {
    const wrapper = mountHistory({
      events: [
        event({
          event_type: 'sla_applied',
          data: { sla_policy_id: 4, resolution_due_at: '2026-10-01T10:00:00Z' },
        }),
      ],
    });

    expect(wrapper.text()).toContain('SLA policy attached');
    expect(wrapper.text()).not.toContain('Set to');
  });

  it('shows an event type this build does not know rather than a blank row', () => {
    const wrapper = mountHistory({
      events: [event({ event_type: 'escalated', data: {} })],
    });

    expect(wrapper.text()).toContain('escalated');
  });

  it('says so when nothing has been recorded yet', () => {
    const wrapper = mountHistory({ events: [] });

    expect(wrapper.text()).toContain('Nothing has been recorded on this case');
    expect(wrapper.find('ul').exists()).toBe(false);
  });

  it('offers to load earlier history only when there is more', () => {
    expect(mountHistory().text()).not.toContain('Load earlier history');
    expect(mountHistory({ hasMore: true }).text()).toContain(
      'Load earlier history'
    );
  });

  it('asks for the earlier history when that is clicked', async () => {
    const wrapper = mountHistory({ hasMore: true });
    const loadMore = wrapper
      .findAll('button')
      .find(button => button.text() === 'Load earlier history');

    await loadMore.trigger('click');

    expect(wrapper.emitted('loadMore')).toHaveLength(1);
  });

  it('refuses to submit an empty note', async () => {
    const wrapper = mountHistory();
    const submit = wrapper
      .findAll('button')
      .find(button => button.text() === 'Add note');

    expect(submit.attributes('disabled')).toBeDefined();

    await submit.trigger('click');

    expect(wrapper.emitted('addNote')).toBeUndefined();
  });

  it('emits the trimmed note and clears the box', async () => {
    const wrapper = mountHistory();

    await wrapper.find('textarea').setValue('  Chased the vendor  ');
    const submit = wrapper
      .findAll('button')
      .find(button => button.text() === 'Add note');
    await submit.trigger('click');

    expect(wrapper.emitted('addNote')).toEqual([['Chased the vendor']]);
    expect(wrapper.find('textarea').element.value).toBe('');
  });

  it('hides the note box on a case that can no longer be worked', () => {
    const wrapper = mountHistory({ canAddNote: false });

    expect(wrapper.find('textarea').exists()).toBe(false);
  });
});
