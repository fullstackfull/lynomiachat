<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Label from 'dashboard/components-next/label/Label.vue';
import {
  PLATFORM_SUPPORT_STATUS_TONES,
  PLATFORM_SUPPORT_PRIORITY_TONES,
} from '../constants';

// A ticket's status, priority or category as a badge. A thin wrapper over the design system's Label with the
// value -> tone map, the same way the tenant desk's TicketEnumLabel does it: the semantic a value carries is
// declared once in constants and the design system turns it into a colour.
const props = defineProps({
  kind: {
    type: String,
    required: true,
    validator: value => ['status', 'priority', 'category'].includes(value),
  },
  // Never blank: every ticket the API returns carries all three.
  value: {
    type: String,
    required: true,
  },
});

const { t } = useI18n();

const TONES = {
  status: PLATFORM_SUPPORT_STATUS_TONES,
  priority: PLATFORM_SUPPORT_PRIORITY_TONES,
  // A category is not a state, so it carries no colour of its own.
  category: {},
};

const tone = computed(() => TONES[props.kind][props.value] || 'neutral');

// A value this build does not know is shown verbatim rather than hidden or guessed at, so a vocabulary
// extended on the server is never a blank chip.
const label = computed(() => {
  const key = `PLATFORM_SUPPORT.ENUMS.${props.kind.toUpperCase()}.${props.value.toUpperCase()}`;
  const translated = t(key);

  return translated === key ? props.value : translated;
});
</script>

<template>
  <Label compact variant="solid" :tone="tone" :label="label" />
</template>
