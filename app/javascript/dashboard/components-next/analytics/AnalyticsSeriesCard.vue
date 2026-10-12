<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { parseISO, format } from 'date-fns';
import BarChart from 'shared/components/charts/BarChart.vue';
import { ANALYTICS_GROUP_BY } from 'dashboard/constants/analytics';

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  // Analytics::Result::Series: [{ bucket: 'YYYY-MM-DD', value: Number }], one entry per bucket including zeros.
  points: {
    type: Array,
    default: () => [],
  },
  groupBy: {
    type: String,
    default: ANALYTICS_GROUP_BY.DAY,
  },
  color: {
    type: String,
    default: 'rgb(var(--blue-9))',
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const BUCKET_LABEL_FORMAT = {
  [ANALYTICS_GROUP_BY.DAY]: 'dd MMM',
  [ANALYTICS_GROUP_BY.WEEK]: 'dd MMM',
  [ANALYTICS_GROUP_BY.MONTH]: 'MMM yyyy',
};

const CHART_HEIGHT = 240;

const total = computed(() =>
  props.points.reduce((sum, point) => sum + Number(point.value || 0), 0)
);

const chartData = computed(() => ({
  categories: props.points.map(point =>
    format(
      parseISO(point.bucket),
      BUCKET_LABEL_FORMAT[props.groupBy] ||
        BUCKET_LABEL_FORMAT[ANALYTICS_GROUP_BY.DAY]
    )
  ),
  series: [
    {
      id: 'value',
      label: props.title,
      color: props.color,
      data: props.points.map(point => Number(point.value || 0)),
    },
  ],
}));

const formatValue = value => Number(value).toLocaleString();
</script>

<template>
  <div
    class="flex flex-col gap-4 p-5 border rounded-overlay bg-n-solid-1 border-n-weak"
  >
    <div class="flex items-start justify-between gap-3">
      <div class="flex flex-col gap-1 min-w-0">
        <span class="text-heading-3 text-n-slate-12">{{ title }}</span>
        <span v-if="description" class="text-label-small text-n-slate-10">
          {{ description }}
        </span>
      </div>
      <span class="font-medium tabular-nums text-body-main text-n-slate-11">
        {{ t('ANALYTICS.SERIES.TOTAL', { value: formatValue(total) }) }}
      </span>
    </div>
    <div
      v-if="loading"
      class="w-full rounded bg-n-slate-3 animate-pulse"
      :style="{ height: `${CHART_HEIGHT}px` }"
    />
    <div
      v-else-if="points.length"
      class="flex items-center justify-center min-w-0"
    >
      <BarChart
        :data="chartData"
        :aria-label="title"
        :format-value="formatValue"
        :height="CHART_HEIGHT"
      />
    </div>
    <span v-else class="text-body-main text-n-slate-10">
      {{ t('ANALYTICS.NO_DATA') }}
    </span>
  </div>
</template>
