<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Select from 'dashboard/components-next/select/Select.vue';
import TicketSlaLabel from './TicketSlaLabel.vue';
import { allowedTicketStatuses } from 'dashboard/helper/supportTicketHelper';
import { TICKET_PRIORITIES } from 'dashboard/constants/supportTickets';

// What a case is, and the two things most often changed about it. The status control offers only the states the
// case can actually reach; the server's transition table stays the authority, and a refusal from it is shown
// with the message it came with.
const props = defineProps({
  ticket: {
    type: Object,
    required: true,
  },
  isSaving: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const statusOptions = computed(() =>
  allowedTicketStatuses(props.ticket.status).map(value => ({
    value,
    label: t(`SUPPORT_TICKETS.ENUMS.STATUS.${value.toUpperCase()}`),
  }))
);

const priorityOptions = computed(() =>
  TICKET_PRIORITIES.map(value => ({
    value,
    label: t(`SUPPORT_TICKETS.ENUMS.PRIORITY.${value.toUpperCase()}`),
  }))
);
</script>

<template>
  <header class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-3">
      <span class="tabular-nums text-body-main text-n-slate-10">
        {{ ticket.reference }}
      </span>
      <TicketSlaLabel :ticket="ticket" />
    </div>
    <h1 class="m-0 text-heading-1 text-n-slate-12">{{ ticket.title }}</h1>
    <div class="flex flex-wrap items-end gap-3">
      <label class="flex flex-col gap-1 text-label-small text-n-slate-10">
        {{ t('SUPPORT_TICKETS.DETAIL.STATUS') }}
        <Select
          :model-value="ticket.status"
          :options="statusOptions"
          :disabled="isSaving"
          @update:model-value="value => emit('update', { status: value })"
        />
      </label>
      <label class="flex flex-col gap-1 text-label-small text-n-slate-10">
        {{ t('SUPPORT_TICKETS.DETAIL.PRIORITY') }}
        <Select
          :model-value="ticket.priority"
          :options="priorityOptions"
          :disabled="isSaving"
          @update:model-value="value => emit('update', { priority: value })"
        />
      </label>
    </div>
  </header>
</template>
