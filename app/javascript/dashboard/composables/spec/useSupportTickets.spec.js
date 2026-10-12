import { flushPromises } from '@vue/test-utils';
import { effectScope, nextTick, ref } from 'vue';
import SupportTicketsAPI from 'dashboard/api/supportTickets';
import {
  useLinkedSupportTickets,
  useSupportTicket,
  useSupportTicketList,
} from '../useSupportTickets';
import { TICKET_PAGE_SIZE } from 'dashboard/constants/supportTickets';

// The composable reads the URL through `useRoute`, so the mock has to be reactive or the watcher it installs
// would never fire. Both the container and the route name it starts on are hoisted, because the factory runs
// while `vue-router` is first imported -- before any ordinary top-level binding in this file exists.
const router = vi.hoisted(() => ({
  name: 'support_tickets_index',
  route: null,
  push: null,
}));

const ROUTE_NAME = router.name;

vi.mock('dashboard/api/supportTickets', () => ({
  default: {
    getTickets: vi.fn(),
    getTicket: vi.fn(),
    getEvents: vi.fn(),
    createNote: vi.fn(),
    updateTicket: vi.fn(),
  },
}));

vi.mock('vue-router', async () => {
  const { ref: createRef } = await import('vue');
  router.route = createRef({ name: router.name, query: {} });
  router.push = vi.fn(target => {
    router.route.value = { name: target.name, query: target.query };
  });

  return {
    useRoute: () => ({
      get name() {
        return router.route.value.name;
      },
      get query() {
        return router.route.value.query;
      },
    }),
    useRouter: () => ({ push: router.push }),
  };
});

const navigate = (name, query = {}) => {
  router.route.value = { name, query };
};

const listResponse = (payload = [], meta = {}) => ({
  data: {
    meta: {
      current_page: 1,
      total_entries: payload.length,
      per_page: TICKET_PAGE_SIZE,
      counts: { all: 9, mine: 2, unassigned: 1, overdue: 0 },
      ...meta,
    },
    payload,
  },
});

const cancelled = () => {
  const error = new Error('canceled');
  error.code = 'ERR_CANCELED';
  return error;
};

describe('useSupportTicketList', () => {
  let scopes = [];

  const build = () => {
    const scope = effectScope();
    scopes.push(() => scope.stop());
    return scope.run(() => useSupportTicketList(ROUTE_NAME));
  };

  beforeEach(() => {
    navigate(ROUTE_NAME);
    router.push.mockClear();
    SupportTicketsAPI.getTickets.mockReset();
  });

  afterEach(() => {
    scopes.forEach(stop => stop());
    scopes = [];
  });

  it('asks for the plain view and the server page size when the URL is empty', async () => {
    SupportTicketsAPI.getTickets.mockResolvedValue(listResponse());
    const list = build();

    await list.fetch();

    expect(SupportTicketsAPI.getTickets.mock.calls[0][0]).toEqual({
      page: 1,
      per_page: TICKET_PAGE_SIZE,
    });
  });

  it('turns the URL query into the request the server takes', async () => {
    navigate(ROUTE_NAME, { view: 'mine', page: '2', priority: 'urgent' });
    SupportTicketsAPI.getTickets.mockResolvedValue(listResponse());
    const list = build();

    await list.fetch();

    expect(SupportTicketsAPI.getTickets.mock.calls[0][0]).toMatchObject({
      assignee_id: 'me',
      status: 'active',
      priority: 'urgent',
      page: 2,
    });
  });

  it('keeps the counts the response carries, so the tabs cannot disagree with the list', async () => {
    SupportTicketsAPI.getTickets.mockResolvedValue(
      listResponse([{ id: 1 }], { total_entries: 9 })
    );
    const list = build();

    await list.fetch();

    expect(list.counts.value).toEqual({
      all: 9,
      mine: 2,
      unassigned: 1,
      overdue: 0,
    });
    expect(list.meta.value).toEqual({
      currentPage: 1,
      totalEntries: 9,
      perPage: TICKET_PAGE_SIZE,
    });
  });

  it('distinguishes an empty page from one that has not loaded', async () => {
    SupportTicketsAPI.getTickets.mockResolvedValue(listResponse());
    const list = build();

    expect(list.isEmpty.value).toBe(false);

    await list.fetch();

    expect(list.isEmpty.value).toBe(true);
    expect(list.hasLoadedOnce.value).toBe(true);
  });

  it('reports loading while the request is in flight', async () => {
    let settle;
    SupportTicketsAPI.getTickets.mockImplementation(
      () =>
        new Promise(resolve => {
          settle = resolve;
        })
    );
    const list = build();

    const pending = list.fetch();
    expect(list.isLoading.value).toBe(true);

    settle(listResponse([{ id: 1 }]));
    await pending;

    expect(list.isLoading.value).toBe(false);
  });

  it('keeps the error and empties the page when the request fails', async () => {
    const failure = new Error('boom');
    SupportTicketsAPI.getTickets.mockRejectedValue(failure);
    const list = build();

    await list.fetch();

    expect(list.error.value).toBe(failure);
    expect(list.tickets.value).toEqual([]);
    expect(list.isEmpty.value).toBe(false);
  });

  it('resets to page one whenever the question changes', () => {
    navigate(ROUTE_NAME, { page: '4', view: 'mine' });
    const list = build();

    list.updateFilters({ priority: 'high' });

    expect(router.push).toHaveBeenCalledWith({
      name: ROUTE_NAME,
      query: { view: 'mine', priority: 'high' },
    });
  });

  it('keeps the rest of the query when only the page changes', () => {
    navigate(ROUTE_NAME, { view: 'mine' });
    const list = build();

    list.setPage(3);

    expect(router.push).toHaveBeenCalledWith({
      name: ROUTE_NAME,
      query: { view: 'mine', page: 3 },
    });
  });

  it('drops the filters a view owns when the view changes', () => {
    navigate(ROUTE_NAME, {
      view: 'mine',
      status: 'open',
      assignee_id: 'me',
      sla: 'overdue',
      q: 'dns',
    });
    const list = build();

    list.setView('closed');

    expect(router.push).toHaveBeenCalledWith({
      name: ROUTE_NAME,
      query: { view: 'closed', q: 'dns' },
    });
  });

  it('keeps the view when the filters are cleared', () => {
    navigate(ROUTE_NAME, { view: 'overdue', q: 'dns', priority: 'high' });
    const list = build();

    list.clearFilters();

    expect(router.push).toHaveBeenCalledWith({
      name: ROUTE_NAME,
      query: { view: 'overdue' },
    });
  });

  it('does not navigate once the operator has left the workspace', () => {
    navigate('support_tickets_show');
    const list = build();

    list.updateFilters({ q: 'late' });

    expect(router.push).not.toHaveBeenCalled();
  });

  it('refetches when the URL changes, and not when another route does', async () => {
    SupportTicketsAPI.getTickets.mockResolvedValue(listResponse());
    build();

    navigate(ROUTE_NAME, { priority: 'high' });
    await nextTick();
    await flushPromises();
    expect(SupportTicketsAPI.getTickets).toHaveBeenCalledTimes(1);

    navigate('support_tickets_show', { ticketId: '4' });
    await nextTick();
    await flushPromises();
    expect(SupportTicketsAPI.getTickets).toHaveBeenCalledTimes(1);
  });

  it('cancels the superseded request so a slow page cannot replace a newer one', async () => {
    SupportTicketsAPI.getTickets
      .mockImplementationOnce(
        (_params, { signal }) =>
          new Promise((_resolve, reject) => {
            signal.addEventListener('abort', () => reject(cancelled()));
          })
      )
      .mockResolvedValueOnce(listResponse([{ id: 'fresh' }]));
    const list = build();

    const first = list.fetch();
    const second = list.fetch();
    await Promise.all([first, second]);
    await flushPromises();

    expect(list.tickets.value.map(entry => entry.id)).toEqual(['fresh']);
    expect(list.error.value).toBeNull();
  });

  it('discards a response that resolved before its cancellation landed', async () => {
    SupportTicketsAPI.getTickets
      .mockResolvedValueOnce(listResponse([{ id: 'stale' }]))
      .mockResolvedValueOnce(listResponse([{ id: 'fresh' }]));
    const list = build();

    const first = list.fetch();
    const second = list.fetch();
    await Promise.all([first, second]);

    expect(list.tickets.value.map(entry => entry.id)).toEqual(['fresh']);
  });
});

describe('useLinkedSupportTickets', () => {
  let scopes = [];

  const build = params => {
    const scope = effectScope();
    scopes.push(() => scope.stop());
    return scope.run(() => useLinkedSupportTickets(ref(params)));
  };

  beforeEach(() => {
    SupportTicketsAPI.getTickets.mockReset();
  });

  afterEach(() => {
    scopes.forEach(stop => stop());
    scopes = [];
  });

  it('asks the list endpoint for the cases linked to one record', async () => {
    SupportTicketsAPI.getTickets.mockResolvedValue(
      listResponse([{ id: 1 }], { total_entries: 4 })
    );
    const panel = build({ conversation_id: 12 });

    await panel.load();

    expect(SupportTicketsAPI.getTickets.mock.calls[0][0]).toEqual({
      conversation_id: 12,
      per_page: TICKET_PAGE_SIZE,
    });
    expect(panel.totalEntries.value).toBe(4);
  });

  it('keeps the error rather than showing an empty panel', async () => {
    const failure = new Error('nope');
    SupportTicketsAPI.getTickets.mockRejectedValue(failure);
    const panel = build({ contact_id: 3 });

    await panel.load();

    expect(panel.error.value).toBe(failure);
    expect(panel.isEmpty.value).toBe(false);
  });
});

describe('useSupportTicket', () => {
  let scopes = [];

  const build = (id = '7') => {
    const scope = effectScope();
    scopes.push(() => scope.stop());
    return scope.run(() => useSupportTicket(ref(id)));
  };

  const eventsPage = (payload, totalEntries = payload.length, page = 1) => ({
    data: {
      meta: { current_page: page, total_entries: totalEntries, per_page: 50 },
      payload,
    },
  });

  beforeEach(() => {
    SupportTicketsAPI.getTicket.mockReset();
    SupportTicketsAPI.getEvents.mockReset();
    SupportTicketsAPI.createNote.mockReset();
    SupportTicketsAPI.updateTicket.mockReset();
  });

  afterEach(() => {
    scopes.forEach(stop => stop());
    scopes = [];
  });

  it('accepts a reference as the id, because an operator pastes one from an email', async () => {
    SupportTicketsAPI.getTicket.mockResolvedValue({
      data: { payload: { id: 7, reference: 'TCK-000007' } },
    });
    const detail = build('TCK-000007');

    await detail.load();

    expect(SupportTicketsAPI.getTicket.mock.calls[0][0]).toBe('TCK-000007');
    expect(detail.ticket.value.reference).toBe('TCK-000007');
  });

  it('appends the next page of history rather than replacing it', async () => {
    SupportTicketsAPI.getEvents
      .mockResolvedValueOnce(eventsPage([{ id: 1 }], 2, 1))
      .mockResolvedValueOnce(eventsPage([{ id: 2 }], 2, 2));
    const detail = build();

    await detail.loadEvents();
    expect(detail.hasMoreEvents.value).toBe(true);

    await detail.loadMoreEvents();

    expect(detail.events.value.map(entry => entry.id)).toEqual([1, 2]);
    expect(SupportTicketsAPI.getEvents.mock.calls[1][1]).toEqual({ page: 2 });
    expect(detail.hasMoreEvents.value).toBe(false);
  });

  it('does nothing when asked for more history it already has', async () => {
    SupportTicketsAPI.getEvents.mockResolvedValue(eventsPage([{ id: 1 }]));
    const detail = build();

    await detail.loadEvents();
    await detail.loadMoreEvents();

    expect(SupportTicketsAPI.getEvents).toHaveBeenCalledTimes(1);
  });

  it('takes the updated case from the response and re-reads the history', async () => {
    SupportTicketsAPI.updateTicket.mockResolvedValue({
      data: { payload: { id: 7, status: 'resolved' } },
    });
    SupportTicketsAPI.getEvents.mockResolvedValue(eventsPage([{ id: 1 }]));
    const detail = build();

    await detail.save({ status: 'resolved' });

    expect(SupportTicketsAPI.updateTicket).toHaveBeenCalledWith('7', {
      status: 'resolved',
    });
    expect(detail.ticket.value.status).toBe('resolved');
    expect(SupportTicketsAPI.getEvents).toHaveBeenCalled();
    expect(detail.isSaving.value).toBe(false);
  });

  it('rethrows a refused change, so the view can show the message it came with', async () => {
    const refusal = new Error('422');
    refusal.response = {
      data: { message: 'closed to in_progress is not allowed' },
    };
    SupportTicketsAPI.updateTicket.mockRejectedValue(refusal);
    const detail = build();

    await expect(detail.save({ status: 'in_progress' })).rejects.toBe(refusal);
    expect(detail.isSaving.value).toBe(false);
  });

  it('pushes a new note onto the trail without refetching the whole history', async () => {
    SupportTicketsAPI.getEvents.mockResolvedValue(eventsPage([{ id: 1 }]));
    SupportTicketsAPI.createNote.mockResolvedValue({
      data: {
        payload: { id: 2, event_type: 'note', body: 'chased the vendor' },
      },
    });
    const detail = build();

    await detail.loadEvents();
    await detail.addNote('chased the vendor');

    expect(SupportTicketsAPI.createNote).toHaveBeenCalledWith(
      '7',
      'chased the vendor'
    );
    expect(detail.events.value.map(entry => entry.id)).toEqual([1, 2]);
    expect(SupportTicketsAPI.getEvents).toHaveBeenCalledTimes(1);
  });
});
