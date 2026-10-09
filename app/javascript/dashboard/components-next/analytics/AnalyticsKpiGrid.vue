<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
// A generic label/value/hint/rate card with its own loading state. It was written for the campaign analytics
// page and carries that name, but nothing in it is campaign specific and both are analytics screens, so it is
// reused here rather than duplicated.
import MetricCard from 'dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignMetricCard.vue';
import {
  ANALYTICS_KPI_KIND,
  ANALYTICS_UNIT,
} from 'dashboard/constants/analytics';

const props = defineProps({
  // Analytics::Result::Kpi list: [{ key, value, unit, kind, comparison? }].
  kpis: {
    type: Array,
    default: () => [],
  },
  // The i18n namespace the labels live under: ANALYTICS.<scope>.KPI.<KEY>.
  scope: {
    type: String,
    required: true,
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const EMPTY_VALUE = '—';

// A duration average is null, not zero, when nothing was measured: "no conversation was resolved" must not
// read as "resolved instantly".
const formatValue = kpi => {
  if (kpi.value === null || kpi.value === undefined) return EMPTY_VALUE;
  if (kpi.unit === ANALYTICS_UNIT.SECONDS) return formatTime(kpi.value);
  if (kpi.unit === ANALYTICS_UNIT.PERCENT) return `${kpi.value}%`;
  return Number(kpi.value).toLocaleString();
};

const cards = computed(() =>
  props.kpis.map(kpi => {
    const isCurrentState = kpi.kind === ANALYTICS_KPI_KIND.CURRENT_STATE;
    return {
      key: kpi.key,
      label: t(`ANALYTICS.${props.scope}.KPI.${kpi.key.toUpperCase()}.LABEL`),
      // A current-state reading is taken now, so its hint says so instead of letting the date range imply it
      // was measured over the selected period.
      hint: isCurrentState
        ? t('ANALYTICS.KPI.CURRENT_STATE_HINT')
        : t(`ANALYTICS.${props.scope}.KPI.${kpi.key.toUpperCase()}.HINT`),
      value: formatValue(kpi),
    };
  })
);
</script>

<template>
  <div
    class="grid grid-cols-1 gap-px overflow-hidden border rounded-overlay border-n-weak bg-n-weak sm:grid-cols-2 lg:grid-cols-4"
  >
    <MetricCard
      v-for="card in cards"
      :key="card.key"
      :label="card.label"
      :value="card.value"
      :hint="card.hint"
      :loading="loading"
    />
  </div>
</template>
