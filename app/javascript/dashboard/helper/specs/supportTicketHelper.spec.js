import {
  allowedTicketStatuses,
  buildTicketRouteQuery,
  hasActiveTicketFilters,
  isTicketActive,
  ticketFiltersFromQuery,
  ticketRequestParams,
  ticketSlaState,
} from '../supportTicketHelper';
import {
  TICKET_PAGE_SIZE,
  TICKET_SLA_STATE,
} from 'dashboard/constants/supportTickets';

const NOW = 1_760_000_000;

const ticket = (sla = {}, status = 'open') => ({
  status,
  sla: {
    applied: true,
    paused: false,
    breached: false,
    resolution_due_at: NOW + 3600,
    ...sla,
  },
});

describe('ticketFiltersFromQuery', () => {
  it('defaults to the first view and the first page', () => {
    expect(ticketFiltersFromQuery({})).toEqual({ view: 'all', page: 1 });
  });

  it('keeps the values the server accepts', () => {
    const filters = ticketFiltersFromQuery({
      view: 'mine',
      page: '3',
      q: 'TCK-000123',
      status: 'in_progress',
      priority: 'urgent',
      category: 'billing',
      sla: 'breached',
      sort: 'created_at_asc',
      assignee_id: '7',
      team_id: '2',
      contact_id: '9',
    });

    expect(filters).toEqual({
      view: 'mine',
      page: 3,
      q: 'TCK-000123',
      status: 'in_progress',
      priority: 'urgent',
      category: 'billing',
      sla: 'breached',
      sort: 'created_at_asc',
      assignee_id: 7,
      team_id: 2,
      contact_id: 9,
    });
  });

  it('accepts the status groups the server resolves', () => {
    expect(ticketFiltersFromQuery({ status: 'active' }).status).toBe('active');
    expect(ticketFiltersFromQuery({ status: 'terminal' }).status).toBe(
      'terminal'
    );
  });

  it('accepts the two assignee literals as they are', () => {
    expect(ticketFiltersFromQuery({ assignee_id: 'me' }).assignee_id).toBe(
      'me'
    );
    expect(
      ticketFiltersFromQuery({ assignee_id: 'unassigned' }).assignee_id
    ).toBe('unassigned');
  });

  it('drops a value the server would refuse, so a stale bookmark still opens', () => {
    const filters = ticketFiltersFromQuery({
      view: 'nonsense',
      status: 'archived',
      priority: 'blocker',
      sla: 'whenever',
      sort: 'title',
      assignee_id: 'someone',
      team_id: '-4',
    });

    expect(filters).toEqual({ view: 'all', page: 1 });
  });

  it('takes a date window only when both ends are present', () => {
    expect(ticketFiltersFromQuery({ since: '100' }).since).toBeUndefined();
    expect(ticketFiltersFromQuery({ until: '200' }).until).toBeUndefined();
    expect(
      ticketFiltersFromQuery({ since: '100', until: '200' })
    ).toMatchObject({ since: 100, until: 200 });
  });

  it('refuses an epoch the column cannot hold', () => {
    const filters = ticketFiltersFromQuery({
      since: '100',
      until: '253402300800',
    });

    expect(filters.since).toBeUndefined();
    expect(filters.until).toBeUndefined();
  });
});

describe('buildTicketRouteQuery', () => {
  it('drops the empty entries a URL must not carry', () => {
    expect(
      buildTicketRouteQuery({
        view: 'mine',
        status: undefined,
        q: '',
        sort: null,
        page: 2,
      })
    ).toEqual({ view: 'mine', page: 2 });
  });
});

describe('ticketRequestParams', () => {
  it('sends the view it was given, with the server page size', () => {
    expect(ticketRequestParams({ view: 'unassigned', page: 1 })).toEqual({
      assignee_id: 'unassigned',
      status: 'active',
      page: 1,
      per_page: TICKET_PAGE_SIZE,
    });
  });

  it('lets an explicit filter narrow the view rather than be ignored', () => {
    const params = ticketRequestParams({
      view: 'mine',
      page: 1,
      status: 'waiting_on_customer',
    });

    expect(params.status).toBe('waiting_on_customer');
    expect(params.assignee_id).toBe('me');
  });

  it('sends nothing but the page for the plain view', () => {
    expect(ticketRequestParams({ view: 'all', page: 2 })).toEqual({
      page: 2,
      per_page: TICKET_PAGE_SIZE,
    });
  });
});

describe('hasActiveTicketFilters', () => {
  it('does not count the view or the page as a narrowing', () => {
    expect(hasActiveTicketFilters({ view: 'mine', page: 4 })).toBe(false);
    expect(hasActiveTicketFilters({ view: 'all', page: 1, q: 'dns' })).toBe(
      true
    );
  });
});

describe('ticketSlaState', () => {
  it('calls a case with no policy none, never on time', () => {
    expect(
      ticketSlaState({ status: 'open', sla: { applied: false } }, NOW)
    ).toBe(TICKET_SLA_STATE.NONE);
  });

  it('trusts the breach the server recorded over the due date', () => {
    expect(
      ticketSlaState(
        ticket({ breached: true, resolution_due_at: NOW + 999 }),
        NOW
      )
    ).toBe(TICKET_SLA_STATE.BREACHED);
  });

  it('reads a terminal case with no breach as met', () => {
    expect(
      ticketSlaState(ticket({ resolution_due_at: NOW - 10 }, 'resolved'), NOW)
    ).toBe(TICKET_SLA_STATE.MET);
  });

  it('reports the paused clock before the due date', () => {
    expect(
      ticketSlaState(ticket({ paused: true, resolution_due_at: NOW - 10 }), NOW)
    ).toBe(TICKET_SLA_STATE.PAUSED);
  });

  it('is overdue once an active case passes its resolution time', () => {
    expect(ticketSlaState(ticket({ resolution_due_at: NOW - 1 }), NOW)).toBe(
      TICKET_SLA_STATE.OVERDUE
    );
  });

  it('is simply due while there is time left', () => {
    expect(ticketSlaState(ticket(), NOW)).toBe(TICKET_SLA_STATE.DUE);
  });
});

describe('allowedTicketStatuses', () => {
  it('lets an active case reach any other status', () => {
    expect(allowedTicketStatuses('open')).toEqual([
      'open',
      'in_progress',
      'waiting_on_customer',
      'waiting_on_internal',
      'resolved',
      'closed',
    ]);
  });

  it('offers a resolved case only closing or reopening', () => {
    expect(allowedTicketStatuses('resolved')).toEqual([
      'open',
      'resolved',
      'closed',
    ]);
  });

  it('offers a closed case only reopening', () => {
    expect(allowedTicketStatuses('closed')).toEqual(['open', 'closed']);
  });
});

describe('isTicketActive', () => {
  it('is true for the four active statuses and false for the terminal ones', () => {
    expect(isTicketActive({ status: 'waiting_on_internal' })).toBe(true);
    expect(isTicketActive({ status: 'closed' })).toBe(false);
    expect(isTicketActive(undefined)).toBe(false);
  });
});
