<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import Label from 'dashboard/components-next/label/Label.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TicketSlaLabel from './TicketSlaLabel.vue';
import { TICKET_CATEGORIES } from 'dashboard/constants/supportTickets';

// Everything about a case that is not its conversation: who it is for, who owns it, what it is about, and when
// each thing happened. The ownership and category controls write straight through, because the alternative is a
// form with a save button whose only job is to delay one field.
const props = defineProps({
  ticket: {
    type: Object,
    required: true,
  },
  contactName: {
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
  isSaving: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const EMPTY_VALUE = '—';
const TIMESTAMP_FORMAT = 'MMM d, yyyy h:mm a';

const agentOptions = computed(() => [
  { value: '', label: t('SUPPORT_TICKETS.DETAIL.PANEL.UNASSIGNED') },
  ...props.agents.map(agent => ({ value: agent.id, label: agent.name })),
]);

const teamOptions = computed(() => [
  { value: '', label: t('SUPPORT_TICKETS.DETAIL.PANEL.NO_TEAM') },
  ...props.teams.map(team => ({ value: team.id, label: team.name })),
]);

const categoryOptions = computed(() =>
  TICKET_CATEGORIES.map(value => ({
    value,
    label: t(`SUPPORT_TICKETS.ENUMS.CATEGORY.${value.toUpperCase()}`),
  }))
);

const labels = computed(() => props.ticket.label_list || []);

// Only the stamps the case actually has. A resolved_at on a case that was reopened is cleared by the server, so
// an absent stamp is a fact about the case and not a gap to fill with a dash.
const timestamps = computed(() =>
  [
    { key: 'CREATED_AT', value: props.ticket.created_at },
    { key: 'LAST_ACTIVITY', value: props.ticket.last_activity_at },
    { key: 'RESOLVED_AT', value: props.ticket.resolved_at },
    { key: 'CLOSED_AT', value: props.ticket.closed_at },
  ].filter(entry => entry.value)
);

// An empty option means "clear this link", which the server accepts as a blank value.
const onAssigneeChange = value =>
  emit('update', { assignee_id: value || null });
const onTeamChange = value => emit('update', { team_id: value || null });
const onCategoryChange = value => emit('update', { category: value });
</script>

<template>
  <aside class="flex flex-col gap-5">
    <div class="flex flex-col gap-1">
      <span class="text-label-small text-n-slate-10">
        {{ t('SUPPORT_TICKETS.DETAIL.PANEL.CONTACT') }}
      </span>
      <RouterLink
        v-if="ticket.contact_id"
        :to="{
          name: 'contacts_edit',
          params: { contactId: ticket.contact_id },
        }"
        class="text-body-main text-n-blue-11 hover:underline"
      >
        {{ contactName || t('SUPPORT_TICKETS.DETAIL.PANEL.VIEW_CONTACT') }}
      </RouterLink>
      <span v-else class="text-body-main text-n-slate-11">
        {{ EMPTY_VALUE }}
      </span>
    </div>

    <label class="flex flex-col gap-1 text-label-small text-n-slate-10">
      {{ t('SUPPORT_TICKETS.DETAIL.PANEL.ASSIGNEE') }}
      <Select
        :model-value="ticket.assignee_id ?? ''"
        class="!w-full [&>select]:w-full"
        :options="agentOptions"
        :disabled="isSaving"
        @update:model-value="onAssigneeChange"
      />
    </label>

    <label class="flex flex-col gap-1 text-label-small text-n-slate-10">
      {{ t('SUPPORT_TICKETS.DETAIL.PANEL.TEAM') }}
      <Select
        :model-value="ticket.team_id ?? ''"
        class="!w-full [&>select]:w-full"
        :options="teamOptions"
        :disabled="isSaving"
        @update:model-value="onTeamChange"
      />
    </label>

    <label class="flex flex-col gap-1 text-label-small text-n-slate-10">
      {{ t('SUPPORT_TICKETS.DETAIL.PANEL.CATEGORY') }}
      <Select
        :model-value="ticket.category"
        class="!w-full [&>select]:w-full"
        :options="categoryOptions"
        :disabled="isSaving"
        @update:model-value="onCategoryChange"
      />
    </label>

    <div class="flex flex-col gap-2">
      <span class="text-label-small text-n-slate-10">
        {{ t('SUPPORT_TICKETS.DETAIL.PANEL.LABELS') }}
      </span>
      <div v-if="labels.length" class="flex flex-wrap gap-1.5">
        <Label v-for="label in labels" :key="label" compact :label="label" />
      </div>
      <span v-else class="text-body-main text-n-slate-11">
        {{ t('SUPPORT_TICKETS.DETAIL.PANEL.NO_LABELS') }}
      </span>
    </div>

    <div class="flex flex-col gap-2">
      <span class="text-label-small text-n-slate-10">
        {{ t('SUPPORT_TICKETS.DETAIL.PANEL.SLA') }}
      </span>
      <TicketSlaLabel :ticket="ticket" class="self-start" />
    </div>

    <div class="flex flex-col gap-2">
      <span class="text-label-small text-n-slate-10">
        {{ t('SUPPORT_TICKETS.DETAIL.PANEL.TIMESTAMPS') }}
      </span>
      <dl class="grid grid-cols-2 gap-x-3 gap-y-1 m-0">
        <template v-for="stamp in timestamps" :key="stamp.key">
          <dt class="m-0 text-label-small text-n-slate-11">
            {{ t(`SUPPORT_TICKETS.DETAIL.PANEL.${stamp.key}`) }}
          </dt>
          <dd class="m-0 tabular-nums text-label-small text-n-slate-12">
            {{ messageTimestamp(stamp.value, TIMESTAMP_FORMAT) }}
          </dd>
        </template>
      </dl>
    </div>
  </aside>
</template>
