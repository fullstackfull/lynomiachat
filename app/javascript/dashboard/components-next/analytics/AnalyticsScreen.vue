<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportHeader from 'dashboard/routes/dashboard/settings/reports/components/ReportHeader.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import AnalyticsRangeControls from './AnalyticsRangeControls.vue';
import AnalyticsKpiGrid from './AnalyticsKpiGrid.vue';
import AnalyticsSeriesCard from './AnalyticsSeriesCard.vue';
import AnalyticsBreakdownCard from './AnalyticsBreakdownCard.vue';
import AnalyticsMetaNote from './AnalyticsMetaNote.vue';
import { useAnalyticsQuery } from 'dashboard/composables/useAnalyticsQuery';

const props = defineProps({
  // The i18n namespace this screen's own copy lives under: ANALYTICS.<scope>.*. Families are kept apart because
  // the same metric key means different things in each -- `delivered` is messages on the WhatsApp screen and
  // recipients on the campaign screen -- and one shared label would be wrong on at least one of them.
  scope: {
    type: String,
    required: true,
  },
  fetcher: {
    type: Function,
    required: true,
  },
  // [{ key, color }] -- one card per series the endpoint returns that this screen draws.
  seriesCards: {
    type: Array,
    default: () => [],
  },
  breakdownDimensions: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();

const breakdownBy = ref(props.breakdownDimensions[0]);

const {
  dateRange,
  groupBy,
  availableGroupBy,
  payload,
  error,
  isLoading,
  hasLoadedOnce,
  load,
  setDateRange,
  setGroupBy,
  setFilters,
} = useAnalyticsQuery((params, options) =>
  props.fetcher({ ...params, breakdown_by: breakdownBy.value }, options)
);

const meta = computed(() => payload.value?.meta || {});
const kpis = computed(() => payload.value?.kpis || []);
const breakdown = computed(() => payload.value?.breakdowns?.[0] || null);
const isInitialLoad = computed(() => isLoading.value && !hasLoadedOnce.value);

const seriesByKey = computed(() =>
  Object.fromEntries(
    (payload.value?.series || []).map(series => [series.key, series])
  )
);

// A 422 from the request boundary carries the reason the request was unusable; anything else is unexpected and
// gets the generic message rather than a raw error pushed at the operator.
const errorMessage = computed(() => {
  if (!error.value) return '';
  return error.value.response?.data?.message || t('ANALYTICS.ERROR.UNEXPECTED');
});

const isEmpty = computed(
  () => hasLoadedOnce.value && !error.value && meta.value.empty
);

const scoped = key => `ANALYTICS.${props.scope}.${key}`;
const metricLabel = key => t(scoped(`KPI.${key.toUpperCase()}.LABEL`));
const metricHint = key => t(scoped(`KPI.${key.toUpperCase()}.HINT`));

const onBreakdownChange = dimension => {
  breakdownBy.value = dimension;
  setFilters({});
};

onMounted(load);
</script>

<template>
  <ReportHeader
    :header-title="t(scoped('HEADER'))"
    :header-description="t(scoped('DESCRIPTION'))"
  />
  <div class="flex flex-col gap-4 pb-6">
    <AnalyticsRangeControls
      :date-range="dateRange"
      :group-by="groupBy"
      :available-group-by="availableGroupBy"
      :timezone="meta.timezone"
      @range-change="setDateRange"
      @group-by-change="setGroupBy"
    />

    <Banner v-if="errorMessage" color="ruby">{{ errorMessage }}</Banner>

    <template v-else>
      <Banner v-if="isEmpty" color="slate">
        {{ t(scoped('EMPTY')) }}
      </Banner>

      <AnalyticsKpiGrid :kpis="kpis" :scope="scope" :loading="isInitialLoad" />

      <div
        v-if="seriesCards.length"
        class="grid grid-cols-1 gap-4 xl:grid-cols-2"
      >
        <AnalyticsSeriesCard
          v-for="card in seriesCards"
          :key="card.key"
          :title="metricLabel(card.key)"
          :description="metricHint(card.key)"
          :points="seriesByKey[card.key]?.points || []"
          :group-by="meta.group_by || groupBy"
          :color="card.color"
          :loading="isInitialLoad"
        />
      </div>

      <AnalyticsBreakdownCard
        v-if="breakdownDimensions.length"
        :title="t('ANALYTICS.BREAKDOWN.TITLE')"
        :rows="breakdown?.rows || []"
        :dimension="breakdownBy"
        :dimensions="breakdownDimensions"
        :scope="scope"
        :loading="isInitialLoad"
        @dimension-change="onBreakdownChange"
      />

      <AnalyticsMetaNote v-if="hasLoadedOnce" :meta="meta" />
    </template>
  </div>
</template>
