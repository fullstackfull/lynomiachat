import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ContactActivityAPI from 'dashboard/api/contactActivity';
import ContactActivity from '../ContactActivity.vue';

withFullI18n();

vi.mock('dashboard/api/contactActivity', () => ({
  default: { get: vi.fn() },
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { contactId: '7' } }),
}));

const page = (payload, nextCursor = null, warnings = []) => ({
  data: { payload, meta: { next_cursor: nextCursor, warnings } },
});

const entry = (id, overrides = {}) => ({
  id,
  source: 'messages',
  category: 'messages',
  kind: 'message_incoming',
  occurred_at: '2026-10-02T10:00:00.000000Z',
  summary: `summary ${id}`,
  meta: {},
  ...overrides,
});

const mountPanel = async () => {
  const wrapper = mount(ContactActivity);
  await flushPromises();
  return wrapper;
};

describe('ContactActivity', () => {
  beforeEach(() => {
    ContactActivityAPI.get.mockReset();
    ContactActivityAPI.get.mockResolvedValue(page([]));
  });

  it('loads the timeline on mount for the contact in the route', async () => {
    await mountPanel();

    expect(ContactActivityAPI.get.mock.calls[0][0]).toBe('7');
  });

  it('renders one row per entry', async () => {
    ContactActivityAPI.get.mockResolvedValue(
      page([entry('messages:1'), entry('messages:2')])
    );

    const wrapper = await mountPanel();

    expect(wrapper.findAll('li')).toHaveLength(2);
    expect(wrapper.text()).toContain('summary messages:1');
  });

  it('offers every filter including All', async () => {
    const wrapper = await mountPanel();
    const labels = wrapper.findAll('button[aria-pressed]').map(b => b.text());

    expect(labels).toEqual([
      'All',
      'Messages',
      'Conversations',
      'Campaigns',
      'Automations',
      'Commerce',
    ]);
  });

  it('marks All as the active filter to begin with', async () => {
    const wrapper = await mountPanel();

    expect(
      wrapper.findAll('button[aria-pressed]')[0].attributes('aria-pressed')
    ).toBe('true');
  });

  it('requests one category when a filter is chosen', async () => {
    const wrapper = await mountPanel();

    await wrapper.findAll('button[aria-pressed]')[5].trigger('click');
    await flushPromises();

    expect(ContactActivityAPI.get.mock.calls[1][1].categories).toEqual([
      'commerce',
    ]);
  });

  it('says nothing has been recorded rather than showing an empty list', async () => {
    const wrapper = await mountPanel();

    expect(wrapper.text()).toContain('Nothing has been recorded');
    expect(wrapper.find('ul').exists()).toBe(false);
  });

  it('offers load more only while a cursor remains, and appends on click', async () => {
    ContactActivityAPI.get
      .mockResolvedValueOnce(page([entry('messages:1')], 'CURSOR1'))
      .mockResolvedValueOnce(page([entry('messages:2')]));

    const wrapper = await mountPanel();
    const loadMore = wrapper
      .findAll('button')
      .find(button => button.text() === 'Load more');

    expect(loadMore).toBeDefined();

    await loadMore.trigger('click');
    await flushPromises();

    expect(wrapper.findAll('li')).toHaveLength(2);
    expect(
      wrapper.findAll('button').some(button => button.text() === 'Load more')
    ).toBe(false);
  });

  it('names the sources that could not be loaded when the response is partial', async () => {
    ContactActivityAPI.get.mockResolvedValue(
      page([entry('messages:1')], null, [
        { scope: 'commerce', reason: 'unavailable' },
      ])
    );

    const wrapper = await mountPanel();

    expect(wrapper.text()).toContain('Some activity could not be loaded');
    expect(wrapper.text()).toContain('commerce');
  });

  it('shows the server reason for a rejected request', async () => {
    ContactActivityAPI.get.mockRejectedValue({
      response: { data: { message: 'That page cursor is not valid.' } },
    });

    const wrapper = await mountPanel();

    expect(wrapper.text()).toContain('That page cursor is not valid.');
    expect(wrapper.find('ul').exists()).toBe(false);
  });
});
