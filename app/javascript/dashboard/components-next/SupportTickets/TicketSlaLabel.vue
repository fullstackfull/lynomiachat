<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Label from 'dashboard/components-next/label/Label.vue';
import { dynamicTime } from 'shared/helpers/timeHelper';
import {
  TICKET_SLA_STATE,
  TICKET_SLA_TONES,
} from 'dashboard/constants/supportTickets';
import { ticketSlaState } from 'dashboard/helper/supportTicketHelper';

// Where a case stands against its SLA. A case with no policy says so rather than reading as on time: every SLA
// figure in this product begins when a policy is attached, so silence is not evidence of a target met.
const props = defineProps({
  ticket: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const MILLISECONDS_PER_SECOND = 1000;

const state = computed(() =>
  ticketSlaState(props.ticket, Math.floor(Date.now() / MILLISECONDS_PER_SECOND))
);

const tone = computed(() => TICKET_SLA_TONES[state.value]);

const dueAt = computed(() => props.ticket.sla?.resolution_due_at);

const label = computed(() => {
  if (state.value === TICKET_SLA_STATE.DUE && dueAt.value) {
    return t('SUPPORT_TICKETS.SLA.DUE', { time: dynamicTime(dueAt.value) });
  }
  return t(`SUPPORT_TICKETS.SLA.${state.value.toUpperCase()}`);
});

const title = computed(() =>
  dueAt.value
    ? t('SUPPORT_TICKETS.SLA.DUE_AT', { time: dynamicTime(dueAt.value) })
    : undefined
);
</script>

<template>
  <span :title="title">
    <Label compact variant="solid" :tone="tone" :label="label" />
  </span>
</template>
