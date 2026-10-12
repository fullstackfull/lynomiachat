<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Label from 'dashboard/components-next/label/Label.vue';
import {
  TICKET_PRIORITY_TONES,
  TICKET_STATUS_TONES,
} from 'dashboard/constants/supportTickets';

// A case's status or its priority, as a badge. One component for both because the only difference is which
// tone map answers: the semantic a value carries is declared once, in constants, and the design system turns it
// into a colour.
const props = defineProps({
  kind: {
    type: String,
    required: true,
    validator: value => ['status', 'priority'].includes(value),
  },
  // Never blank: every case the API returns carries both a status and a priority.
  value: {
    type: String,
    required: true,
  },
});

const { t } = useI18n();

const TONES = {
  status: TICKET_STATUS_TONES,
  priority: TICKET_PRIORITY_TONES,
};

const tone = computed(() => TONES[props.kind][props.value] || 'neutral');

// A value this build does not know is shown verbatim rather than hidden or guessed at, so a status added on the
// server is never a blank cell.
const label = computed(() => {
  const key = `SUPPORT_TICKETS.ENUMS.${props.kind.toUpperCase()}.${props.value.toUpperCase()}`;
  return TONES[props.kind][props.value] ? t(key) : props.value;
});
</script>

<template>
  <Label compact variant="solid" :tone="tone" :label="label" />
</template>
