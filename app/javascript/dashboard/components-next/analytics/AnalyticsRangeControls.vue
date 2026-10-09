<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { ANALYTICS_GROUP_BY } from 'dashboard/constants/analytics';

const props = defineProps({
  dateRange: {
    type: Array,
    required: true,
  },
  groupBy: {
    type: String,
    required: true,
  },
  availableGroupBy: {
    type: Array,
    default: () => Object.values(ANALYTICS_GROUP_BY),
  },
  timezone: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['rangeChange', 'groupByChange']);

const { t } = useI18n();

const groupByTabs = computed(() =>
  props.availableGroupBy.map(option => ({
    label: t(`ANALYTICS.GROUP_BY.${option.toUpperCase()}`),
    value: option,
  }))
);

const activeGroupByIndex = computed(() =>
  Math.max(
    groupByTabs.value.findIndex(tab => tab.value === props.groupBy),
    0
  )
);

// The date picker hands back [start, end, rangeType]; only the two dates matter here, because the range type is
// a picker affordance and the request is made of calendar dates.
const onDateRangeChanged = value => emit('rangeChange', [value[0], value[1]]);
</script>

<template>
  <div class="flex flex-col gap-3 lg:flex-row lg:items-center">
    <WootDatePicker
      :date-range="dateRange"
      @date-range-changed="onDateRangeChanged"
    />
    <TabBar
      :tabs="groupByTabs"
      :initial-active-tab="activeGroupByIndex"
      @tab-changed="tab => emit('groupByChange', tab.value)"
    />
    <span
      v-if="timezone"
      class="text-label-small text-n-slate-10 lg:ms-auto"
      :title="t('ANALYTICS.TIMEZONE_NOTE')"
    >
      {{ t('ANALYTICS.TIMEZONE_LABEL', { timezone }) }}
    </span>
  </div>
</template>
