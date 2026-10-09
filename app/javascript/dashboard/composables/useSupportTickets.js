import { computed, ref, shallowRef, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import SupportTicketsAPI from 'dashboard/api/supportTickets';
import { useAbortableRequest } from './useAbortableRequest';
import { TICKET_PAGE_SIZE } from 'dashboard/constants/supportTickets';
import {
  buildTicketRouteQuery,
  hasActiveTicketFilters,
  ticketFiltersFromQuery,
  ticketRequestParams,
} from 'dashboard/helper/supportTicketHelper';

const emptyMeta = () => ({
  currentPage: 1,
  totalEntries: 0,
  perPage: TICKET_PAGE_SIZE,
});

const readMeta = meta => ({
  currentPage: Number(meta?.current_page) || 1,
  totalEntries: Number(meta?.total_entries) || 0,
  perPage: Number(meta?.per_page) || TICKET_PAGE_SIZE,
});

/**
 * The support workspace's list, driven entirely by the URL query
 * (docs/p9/02-support-tickets.md).
 *
 * The URL is the single source of truth: the view tabs, the filter bar, the
 * sortable headings and the pagination footer all navigate, and one watcher on
 * `route.query` refetches. Nothing holds a second copy of the filters, so the
 * list can never disagree with the address bar, and a view is linkable.
 *
 * Two guards, not one. Requests go through the shared abortable-request helper,
 * so a superseded request is cancelled on the wire; `activeFetchId` then
 * discards a response that had already arrived before its cancellation landed,
 * which is the case the signal alone cannot catch.
 *
 * @param {string} routeName - The route that owns this list. A debounced search
 *   can resolve after the operator has navigated away, and neither the push nor
 *   the refetch should follow them there.
 * @returns {object} The page, its counts, and the navigation that changes them.
 */
export function useSupportTicketList(routeName) {
  const route = useRoute();
  const router = useRouter();
  const { run, isPending } = useAbortableRequest();

  const tickets = shallowRef([]);
  const meta = ref(emptyMeta());
  const counts = ref({});
  const error = ref(null);
  const hasLoadedOnce = ref(false);

  let activeFetchId = 0;

  const filters = computed(() => ticketFiltersFromQuery(route.query));
  const requestParams = computed(() => ticketRequestParams(filters.value));
  const hasActiveFilters = computed(() =>
    hasActiveTicketFilters(filters.value)
  );
  const isEmpty = computed(
    () => hasLoadedOnce.value && !error.value && tickets.value.length === 0
  );

  const fetch = async () => {
    activeFetchId += 1;
    const fetchId = activeFetchId;
    error.value = null;

    try {
      const response = await run(
        signal => SupportTicketsAPI.getTickets(requestParams.value, { signal }),
        { onAbort: null }
      );
      if (response === null || fetchId !== activeFetchId) return;

      tickets.value = response.data.payload || [];
      meta.value = readMeta(response.data.meta);
      counts.value = response.data.meta?.counts || {};
      hasLoadedOnce.value = true;
    } catch (requestError) {
      if (fetchId !== activeFetchId) return;
      error.value = requestError;
      tickets.value = [];
      meta.value = emptyMeta();
    }
  };

  const updateQuery = partial => {
    if (route.name !== routeName) return;
    router.push({
      name: routeName,
      query: buildTicketRouteQuery({ ...route.query, ...partial }),
    });
  };

  // Any change to what is being asked starts again at page one: page 3 of the previous question is not page 3
  // of this one.
  const updateFilters = partial => updateQuery({ ...partial, page: undefined });

  const setPage = page => updateQuery({ page });

  const setSort = sort => updateFilters({ sort });

  // A view carries its own status and assignee, so switching views drops the filters that would fight it and
  // keeps the ones that still read as a narrowing.
  const setView = view =>
    updateFilters({
      view,
      status: undefined,
      assignee_id: undefined,
      sla: undefined,
    });

  const clearFilters = () =>
    router.push({
      name: routeName,
      query: buildTicketRouteQuery({ view: route.query.view }),
    });

  watch(
    () => route.query,
    () => {
      if (route.name === routeName) fetch();
    }
  );

  return {
    tickets,
    meta,
    counts,
    filters,
    requestParams,
    error,
    isLoading: isPending,
    hasLoadedOnce,
    hasActiveFilters,
    isEmpty,
    fetch,
    updateFilters,
    setPage,
    setSort,
    setView,
    clearFilters,
  };
}

/**
 * The cases linked to one record -- a contact, or a conversation -- for the
 * panels that show them beside it.
 *
 * The same list endpoint, with a fixed link filter and no URL involvement:
 * these panels are a reading of one record, not a view somebody navigates
 * through, so they take the first page and offer a link to the workspace for
 * the rest.
 *
 * @param {import('vue').Ref<object>} params - The link filter, e.g.
 *   `{ contact_id: 7 }`. Reactive, so a panel follows the record it sits beside.
 * @returns {object} The cases and the request's state.
 */
export function useLinkedSupportTickets(params) {
  const { run, isPending } = useAbortableRequest();

  const tickets = shallowRef([]);
  const totalEntries = ref(0);
  const error = ref(null);
  const hasLoadedOnce = ref(false);

  let activeFetchId = 0;

  const isEmpty = computed(
    () => hasLoadedOnce.value && !error.value && tickets.value.length === 0
  );

  const load = async () => {
    activeFetchId += 1;
    const fetchId = activeFetchId;
    error.value = null;

    try {
      const response = await run(
        signal =>
          SupportTicketsAPI.getTickets(
            { ...params.value, per_page: TICKET_PAGE_SIZE },
            { signal }
          ),
        { onAbort: null }
      );
      if (response === null || fetchId !== activeFetchId) return;

      tickets.value = response.data.payload || [];
      totalEntries.value = Number(response.data.meta?.total_entries) || 0;
      hasLoadedOnce.value = true;
    } catch (requestError) {
      if (fetchId !== activeFetchId) return;
      error.value = requestError;
      tickets.value = [];
    }
  };

  return {
    tickets,
    totalEntries,
    error,
    isLoading: isPending,
    hasLoadedOnce,
    isEmpty,
    load,
  };
}

/**
 * One case and its history, for the detail view
 * (docs/p9/01-architecture.md §7).
 *
 * History accumulates downwards: the endpoint returns the oldest entries first,
 * so the next page appends. Every write refetches nothing -- the response
 * carries the updated case, and a note is pushed onto the trail -- so the view
 * never shows a state the server did not just confirm.
 *
 * @param {import('vue').Ref<string|number>} ticketId - An id or a reference.
 * @returns {object} The case, its history, and the writes that change them.
 */
export function useSupportTicket(ticketId) {
  const { run: runTicket, isPending: isLoadingTicket } = useAbortableRequest();
  const { run: runEvents, isPending: isLoadingEvents } = useAbortableRequest();

  const ticket = ref(null);
  const events = shallowRef([]);
  const eventsMeta = ref(emptyMeta());
  const error = ref(null);
  const isSaving = ref(false);

  let activeTicketFetchId = 0;

  const hasMoreEvents = computed(
    () => events.value.length < eventsMeta.value.totalEntries
  );

  const load = async () => {
    activeTicketFetchId += 1;
    const fetchId = activeTicketFetchId;
    error.value = null;

    try {
      const response = await runTicket(
        signal => SupportTicketsAPI.getTicket(ticketId.value, { signal }),
        { onAbort: null }
      );
      if (response === null || fetchId !== activeTicketFetchId) return;
      ticket.value = response.data.payload;
    } catch (requestError) {
      if (fetchId !== activeTicketFetchId) return;
      error.value = requestError;
    }
  };

  const loadEvents = async (page = 1) => {
    const response = await runEvents(
      signal =>
        SupportTicketsAPI.getEvents(ticketId.value, { page }, { signal }),
      { onAbort: null }
    );
    if (response === null) return;

    const payload = response.data.payload || [];
    events.value = page === 1 ? payload : [...events.value, ...payload];
    eventsMeta.value = readMeta(response.data.meta);
  };

  const loadMoreEvents = () => {
    if (!hasMoreEvents.value) return Promise.resolve();
    return loadEvents(eventsMeta.value.currentPage + 1);
  };

  // Rethrown, not swallowed: a refused change carries a message already written for a human -- a disallowed
  // status transition names the attempted edge and the allowed set -- and the view shows that message rather
  // than wording its own.
  const save = async attributes => {
    isSaving.value = true;
    try {
      const response = await SupportTicketsAPI.updateTicket(
        ticketId.value,
        attributes
      );
      ticket.value = response.data.payload;
      await loadEvents();
      return ticket.value;
    } finally {
      isSaving.value = false;
    }
  };

  const addNote = async body => {
    isSaving.value = true;
    try {
      const response = await SupportTicketsAPI.createNote(ticketId.value, body);
      events.value = [...events.value, response.data.payload];
      eventsMeta.value = {
        ...eventsMeta.value,
        totalEntries: eventsMeta.value.totalEntries + 1,
      };
      return response.data.payload;
    } finally {
      isSaving.value = false;
    }
  };

  return {
    ticket,
    events,
    eventsMeta,
    error,
    isLoading: isLoadingTicket,
    isLoadingEvents,
    isSaving,
    hasMoreEvents,
    load,
    loadEvents,
    loadMoreEvents,
    save,
    addNote,
  };
}
