import { flushPromises } from '@vue/test-utils';
import { effectScope } from 'vue';
import { useAnalyticsQuery } from '../useAnalyticsQuery';

// 2026-03-15, so a "last 30 days" default resolves to a range that is readable in an assertion.
const NOW = new Date(2026, 2, 15, 13, 45, 0);

const withQuery = fetcher => {
  const scope = effectScope();
  const query = scope.run(() => useAnalyticsQuery(fetcher));
  return { query, stop: () => scope.stop() };
};

describe('useAnalyticsQuery', () => {
  let scopes = [];

  const build = fetcher => {
    const created = withQuery(fetcher);
    scopes.push(created.stop);
    return created.query;
  };

  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
  });

  afterEach(() => {
    scopes.forEach(stop => stop());
    scopes = [];
    vi.useRealTimers();
  });

  it('sends calendar dates rather than instants, so the account timezone decides the buckets', async () => {
    const fetcher = vi.fn().mockResolvedValue({ data: {} });
    const query = build(fetcher);

    await query.load();

    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(fetcher.mock.calls[0][0]).toEqual({
      since: '2026-02-14',
      until: '2026-03-15',
      group_by: 'day',
    });
  });

  it('exposes the payload once loaded', async () => {
    const payload = { meta: { empty: false }, kpis: [{ key: 'a', value: 1 }] };
    const query = build(() => Promise.resolve({ data: payload }));

    await query.load();

    expect(query.payload.value).toEqual(payload);
    expect(query.hasLoadedOnce.value).toBe(true);
    expect(query.error.value).toBeNull();
  });

  it('keeps the error and leaves the previous payload untouched when a request fails', async () => {
    const failure = new Error('boom');
    const fetcher = vi
      .fn()
      .mockResolvedValueOnce({ data: { meta: { empty: false } } })
      .mockRejectedValueOnce(failure);
    const query = build(fetcher);

    await query.load();
    await query.load();

    expect(query.error.value).toBe(failure);
    expect(query.payload.value).toEqual({ meta: { empty: false } });
  });

  it('offers every grouping for a short range', () => {
    const query = build(() => Promise.resolve({ data: {} }));

    expect(query.availableGroupBy.value).toEqual(['day', 'week', 'month']);
  });

  it('drops daily grouping once the range exceeds the daily bucket ceiling', async () => {
    const query = build(() => Promise.resolve({ data: {} }));

    // Eighteen months: past the 366 daily buckets the server allows, inside the 104 weekly ones.
    await query.setDateRange([new Date(2024, 6, 1), new Date(2025, 11, 31)]);

    expect(query.availableGroupBy.value).toEqual(['week', 'month']);
  });

  it('drops weekly grouping too once the range exceeds the weekly bucket ceiling', async () => {
    const query = build(() => Promise.resolve({ data: {} }));

    await query.setDateRange([new Date(2023, 0, 1), new Date(2026, 0, 1)]);

    expect(query.availableGroupBy.value).toEqual(['month']);
  });

  it('moves group_by to a grouping the range supports rather than sending one the server would reject', async () => {
    const fetcher = vi.fn().mockResolvedValue({ data: {} });
    const query = build(fetcher);

    await query.setDateRange([new Date(2023, 0, 1), new Date(2026, 0, 1)]);

    expect(query.groupBy.value).toBe('month');
    expect(fetcher.mock.calls.at(-1)[0].group_by).toBe('month');
  });

  it('keeps an explicitly chosen grouping that the range still supports', async () => {
    const fetcher = vi.fn().mockResolvedValue({ data: {} });
    const query = build(fetcher);

    await query.setGroupBy('week');
    await query.setDateRange([new Date(2026, 0, 1), new Date(2026, 1, 1)]);

    expect(query.groupBy.value).toBe('week');
  });

  it('merges filters into the request', async () => {
    const fetcher = vi.fn().mockResolvedValue({ data: {} });
    const query = build(fetcher);

    await query.setFilters({ inbox_id: 9 });

    expect(fetcher.mock.calls.at(-1)[0].inbox_id).toBe(9);
  });

  it('discards a superseded response so a slow earlier request cannot overwrite fresher data', async () => {
    // Modelled on axios: an aborted request rejects with a CanceledError rather than resolving late.
    const fetcher = vi
      .fn()
      .mockImplementationOnce(
        (params, { signal }) =>
          new Promise((resolve, reject) => {
            signal.addEventListener('abort', () => {
              const cancelled = new Error('canceled');
              cancelled.code = 'ERR_CANCELED';
              reject(cancelled);
            });
          })
      )
      .mockResolvedValueOnce({ data: { meta: { source: 'second' } } });
    const query = build(fetcher);

    const first = query.load();
    const second = query.load();
    await Promise.all([first, second]);
    await flushPromises();

    expect(query.payload.value).toEqual({ meta: { source: 'second' } });
    expect(query.error.value).toBeNull();
  });
});
