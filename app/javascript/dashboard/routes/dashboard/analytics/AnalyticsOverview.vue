<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AnalyticsAPI from 'dashboard/api/analytics';
import ReportHeader from 'dashboard/routes/dashboard/settings/reports/components/ReportHeader.vue';
import AnalyticsRangeControls from 'dashboard/components-next/analytics/AnalyticsRangeControls.vue';
import AnalyticsKpiGrid from 'dashboard/components-next/analytics/AnalyticsKpiGrid.vue';
import AnalyticsSeriesCard from 'dashboard/components-next/analytics/AnalyticsSeriesCard.vue';
import AnalyticsBreakdownCard from 'dashboard/components-next/analytics/AnalyticsBreakdownCard.vue';
import AnalyticsMetaNote from 'dashboard/components-next/analytics/AnalyticsMetaNote.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { useAnalyticsQuery } from 'dashboard/composables/useAnalyticsQuery';
import { ANALYTICS_BREAKDOWN_DIMENSIONS } from 'dashboard/constants/analytics';

const { t } = useI18n();

// Each series answers one operational question, which is why there are four and not one per available metric:
// how much arrived, how much closed, and the two message directions that show whether the team is replying.
const SERIES_CARDS = [
  { key: 'conversations_created', color: 'rgb(var(--blue-9))' },
  { key: 'conversations_resolved', color: 'rgb(var(--teal-9))' },
  { key: 'inbound_messages', color: 'rgb(var(--iris-9))' },
  { key: 'outbound_messages', color: 'rgb(var(--amber-9))' },
];

const breakdownBy = ref(ANALYTICS_BREAKDOWN_DIMENSIONS[0]);

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
} = useAnalyticsQuery((params, { signal }) =>
  AnalyticsAPI.getOverview(
    { ...params, breakdown_by: breakdownBy.value },
    { signal }
  )
);

const meta = computed(() => payload.value?.meta || {});
const kpis = computed(() => payload.value?.kpis || []);
const breakdown = computed(() => payload.value?.breakdowns?.[0] || null);

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

const onBreakdownChange = dimension => {
  breakdownBy.value = dimension;
  setFilters({});
};

onMounted(load);
</script>

<template>
  <ReportHeader
    :header-title="t('ANALYTICS.OVERVIEW.HEADER')"
    :header-description="t('ANALYTICS.OVERVIEW.DESCRIPTION')"
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
        {{ t('ANALYTICS.OVERVIEW.EMPTY') }}
      </Banner>

      <AnalyticsKpiGrid :kpis="kpis" :loading="isLoading && !hasLoadedOnce" />

      <div class="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <AnalyticsSeriesCard
          v-for="card in SERIES_CARDS"
          :key="card.key"
          :title="t(`ANALYTICS.KPI.${card.key.toUpperCase()}.LABEL`)"
          :description="t(`ANALYTICS.KPI.${card.key.toUpperCase()}.HINT`)"
          :points="seriesByKey[card.key]?.points || []"
          :group-by="meta.group_by || groupBy"
          :color="card.color"
          :loading="isLoading && !hasLoadedOnce"
        />
      </div>

      <AnalyticsBreakdownCard
        :title="t('ANALYTICS.BREAKDOWN.TITLE')"
        :rows="breakdown?.rows || []"
        :dimension="breakdownBy"
        :dimensions="ANALYTICS_BREAKDOWN_DIMENSIONS"
        :loading="isLoading && !hasLoadedOnce"
        @dimension-change="onBreakdownChange"
      />

      <AnalyticsMetaNote v-if="hasLoadedOnce" :meta="meta" />
    </template>
  </div>
</template>
