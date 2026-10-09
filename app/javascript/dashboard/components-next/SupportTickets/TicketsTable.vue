<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import TicketEnumLabel from './TicketEnumLabel.vue';
import TicketSlaLabel from './TicketSlaLabel.vue';
import { TICKET_DEFAULT_SORT } from 'dashboard/constants/supportTickets';

// The workspace's list. Presentation only: BaseTable renders the arrow it is given and emits the heading that
// was clicked, and this component translates that into the server's sort vocabulary. The page owns the query.
const props = defineProps({
  tickets: {
    type: Array,
    default: () => [],
  },
  loading: {
    type: Boolean,
    default: false,
  },
  // The server sort key currently in force, as it appears in the URL.
  sort: {
    type: String,
    default: '',
  },
  agents: {
    type: Array,
    default: () => [],
  },
  teams: {
    type: Array,
    default: () => [],
  },
  noDataMessage: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['sort']);

const { t } = useI18n();

const EMPTY_VALUE = '—';

// Which heading each server sort key draws its arrow on, and in which direction. Read from the key rather than
// stored separately, so the arrow cannot disagree with the order the rows actually arrived in.
const SORT_STATE = {
  last_activity_at: { key: 'last_activity_at', order: 'desc' },
  last_activity_at_asc: { key: 'last_activity_at', order: 'asc' },
  created_at: { key: 'created_at', order: 'desc' },
  created_at_asc: { key: 'created_at', order: 'asc' },
  resolution_due_at: { key: 'resolution_due_at', order: 'asc' },
  priority: { key: 'priority', order: 'desc' },
};

// The reverse map. `resolution_due_at` and `priority` have one direction each on the server, so clicking those
// headings twice re-asks the same question instead of promising an order the server cannot give.
const SORT_KEYS = {
  last_activity_at: { asc: 'last_activity_at_asc', desc: 'last_activity_at' },
  resolution_due_at: { asc: 'resolution_due_at', desc: 'resolution_due_at' },
  priority: { asc: 'priority', desc: 'priority' },
};

// Index-aligned with `tableHeaders`.
const SORTABLE_COLUMNS = [
  null,
  null,
  null,
  null,
  'priority',
  null,
  'resolution_due_at',
  'last_activity_at',
];

// Index-aligned with `tableHeaders`: what a narrow viewport drops first. Reference, subject, status and the
// SLA state are what the list is read for, so they stay at every width.
const COLUMN_CLASSES = [
  '',
  '',
  'hidden sm:table-cell',
  '',
  'hidden md:table-cell',
  'hidden lg:table-cell',
  'hidden md:table-cell',
  'hidden sm:table-cell',
];

const tableHeaders = computed(() => [
  t('SUPPORT_TICKETS.TABLE.REFERENCE'),
  t('SUPPORT_TICKETS.TABLE.SUBJECT'),
  t('SUPPORT_TICKETS.TABLE.CONTACT'),
  t('SUPPORT_TICKETS.TABLE.STATUS'),
  t('SUPPORT_TICKETS.TABLE.PRIORITY'),
  t('SUPPORT_TICKETS.TABLE.OWNER'),
  t('SUPPORT_TICKETS.TABLE.SLA'),
  t('SUPPORT_TICKETS.TABLE.LAST_ACTIVITY'),
]);

const sortState = computed(
  () => SORT_STATE[props.sort] || SORT_STATE[TICKET_DEFAULT_SORT]
);

const agentNames = computed(() =>
  Object.fromEntries(props.agents.map(agent => [agent.id, agent.name]))
);

const teamNames = computed(() =>
  Object.fromEntries(props.teams.map(team => [team.id, team.name]))
);

// Who the case sits with. The assignee answers it when there is one; otherwise the team does, because an
// unassigned case in a queue is not the same as an unassigned case in nobody's queue.
const ownerFor = ticket =>
  agentNames.value[ticket.assignee_id] ||
  teamNames.value[ticket.team_id] ||
  t('SUPPORT_TICKETS.TABLE.UNASSIGNED');

const onSort = ({ key, order }) => {
  const mapped = SORT_KEYS[key]?.[order];
  if (mapped) emit('sort', mapped);
};
</script>

<template>
  <BaseTable
    sticky-header
    :headers="tableHeaders"
    :items="tickets"
    :loading="loading"
    :loading-message="t('SUPPORT_TICKETS.LOADING')"
    :loading-rows="8"
    :column-classes="COLUMN_CLASSES"
    :sortable-columns="SORTABLE_COLUMNS"
    :sort-by="sortState.key"
    :sort-order="sortState.order"
    :no-data-message="noDataMessage"
    @sort="onSort"
  >
    <template #row="{ items }">
      <BaseTableRow v-for="ticket in items" :key="ticket.id" :item="ticket">
        <template #default>
          <BaseTableCell>
            <RouterLink
              :to="{
                name: 'support_tickets_show',
                params: { ticketId: ticket.id },
              }"
              class="tabular-nums whitespace-nowrap text-body-main text-n-blue-11 hover:underline"
            >
              {{ ticket.reference }}
            </RouterLink>
          </BaseTableCell>

          <BaseTableCell>
            <RouterLink
              :to="{
                name: 'support_tickets_show',
                params: { ticketId: ticket.id },
              }"
              class="block max-w-xs truncate text-body-main text-n-slate-12 hover:underline"
              :title="ticket.title"
            >
              {{ ticket.title }}
            </RouterLink>
          </BaseTableCell>

          <BaseTableCell class="hidden sm:table-cell">
            <span class="truncate text-body-main text-n-slate-11">
              {{ ticket.contact_name || EMPTY_VALUE }}
            </span>
          </BaseTableCell>

          <BaseTableCell>
            <TicketEnumLabel kind="status" :value="ticket.status" />
          </BaseTableCell>

          <BaseTableCell class="hidden md:table-cell">
            <TicketEnumLabel kind="priority" :value="ticket.priority" />
          </BaseTableCell>

          <BaseTableCell class="hidden lg:table-cell">
            <span class="truncate text-body-main text-n-slate-11">
              {{ ownerFor(ticket) }}
            </span>
          </BaseTableCell>

          <BaseTableCell class="hidden md:table-cell">
            <TicketSlaLabel :ticket="ticket" />
          </BaseTableCell>

          <BaseTableCell class="hidden sm:table-cell">
            <span class="whitespace-nowrap text-body-main text-n-slate-11">
              {{
                messageTimestamp(ticket.last_activity_at, 'MMM d, yyyy h:mm a')
              }}
            </span>
          </BaseTableCell>
        </template>
      </BaseTableRow>
    </template>
  </BaseTable>
</template>
