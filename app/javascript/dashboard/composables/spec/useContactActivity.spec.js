import { flushPromises } from '@vue/test-utils';
import { effectScope, ref } from 'vue';
import ContactActivityAPI from 'dashboard/api/contactActivity';
import { useContactActivity } from '../useContactActivity';
import { CONTACT_ACTIVITY_PAGE_SIZE } from 'dashboard/constants/contactActivity';

vi.mock('dashboard/api/contactActivity', () => ({
  default: { get: vi.fn() },
}));

const page = (payload, nextCursor = null, warnings = []) => ({
  data: { payload, meta: { next_cursor: nextCursor, warnings } },
});

describe('useContactActivity', () => {
  let scopes = [];

  const build = () => {
    const scope = effectScope();
    scopes.push(() => scope.stop());
    return scope.run(() => useContactActivity(ref('7')));
  };

  beforeEach(() => {
    ContactActivityAPI.get.mockReset();
  });

  afterEach(() => {
    scopes.forEach(stop => stop());
    scopes = [];
  });

  it('asks for every category when no filter is set', async () => {
    ContactActivityAPI.get.mockResolvedValue(page([]));
    const activity = build();

    await activity.load();

    const [contactId, params] = ContactActivityAPI.get.mock.calls[0];
    expect(contactId).toBe('7');
    expect(params.categories).toBeUndefined();
    expect(params.limit).toBe(CONTACT_ACTIVITY_PAGE_SIZE);
    expect(params.cursor).toBeUndefined();
  });

  it('appends the next page rather than replacing the list', async () => {
    ContactActivityAPI.get
      .mockResolvedValueOnce(page([{ id: 'a' }], 'CURSOR1'))
      .mockResolvedValueOnce(page([{ id: 'b' }]));
    const activity = build();

    await activity.load();
    expect(activity.hasMore.value).toBe(true);

    await activity.loadMore();

    expect(activity.entries.value.map(entry => entry.id)).toEqual(['a', 'b']);
    expect(ContactActivityAPI.get.mock.calls[1][1].cursor).toBe('CURSOR1');
    expect(activity.hasMore.value).toBe(false);
  });

  it('does nothing when asked for more with no cursor', async () => {
    ContactActivityAPI.get.mockResolvedValue(page([{ id: 'a' }]));
    const activity = build();

    await activity.load();
    await activity.loadMore();

    expect(ContactActivityAPI.get).toHaveBeenCalledTimes(1);
  });

  it('starts a new list when the category changes, without a stale cursor', async () => {
    ContactActivityAPI.get
      .mockResolvedValueOnce(page([{ id: 'a' }], 'CURSOR1'))
      .mockResolvedValueOnce(page([{ id: 'c' }]));
    const activity = build();

    await activity.load();
    await activity.setCategory('commerce');

    expect(activity.entries.value.map(entry => entry.id)).toEqual(['c']);
    expect(ContactActivityAPI.get.mock.calls[1][1]).toMatchObject({
      categories: ['commerce'],
      cursor: undefined,
    });
  });

  it('reports a partial response so the viewer knows something was left out', async () => {
    ContactActivityAPI.get.mockResolvedValue(
      page([{ id: 'a' }], null, [{ scope: 'commerce', reason: 'unavailable' }])
    );
    const activity = build();

    await activity.load();

    expect(activity.isPartial.value).toBe(true);
    expect(activity.warnings.value).toEqual([
      { scope: 'commerce', reason: 'unavailable' },
    ]);
  });

  it('distinguishes an empty timeline from one that has not loaded', async () => {
    ContactActivityAPI.get.mockResolvedValue(page([]));
    const activity = build();

    expect(activity.isEmpty.value).toBe(false);

    await activity.load();

    expect(activity.isEmpty.value).toBe(true);
  });

  it('keeps the error and does not mark the list empty when the request fails', async () => {
    const failure = new Error('boom');
    ContactActivityAPI.get.mockRejectedValue(failure);
    const activity = build();

    await activity.load();

    expect(activity.error.value).toBe(failure);
    expect(activity.isEmpty.value).toBe(false);
  });

  it('discards a superseded response so a slow filter change cannot append the wrong rows', async () => {
    ContactActivityAPI.get
      .mockImplementationOnce(
        (_id, _params, { signal }) =>
          new Promise((resolve, reject) => {
            signal.addEventListener('abort', () => {
              const cancelled = new Error('canceled');
              cancelled.code = 'ERR_CANCELED';
              reject(cancelled);
            });
          })
      )
      .mockResolvedValueOnce(page([{ id: 'fresh' }]));
    const activity = build();

    const first = activity.load();
    const second = activity.setCategory('messages');
    await Promise.all([first, second]);
    await flushPromises();

    expect(activity.entries.value.map(entry => entry.id)).toEqual(['fresh']);
    expect(activity.error.value).toBeNull();
  });
});
