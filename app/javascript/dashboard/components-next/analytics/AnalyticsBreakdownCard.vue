<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  // Analytics::Result::Breakdown rows: [{ id, label, value }], already ordered by value descending.
  rows: {
    type: Array,
    default: () => [],
  },
  dimension: {
    type: String,
    required: true,
  },
  dimensions: {
    type: Array,
    default: () => [],
  },
  // The i18n namespace the dimension names live under: ANALYTICS.<scope>.BREAKDOWN.<DIMENSION>.
  scope: {
    type: String,
    required: true,
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['dimensionChange']);

const { t } = useI18n();

// Enough rows to answer "where does the volume sit" without turning the card into a table nobody scrolls.
const VISIBLE_ROWS = 8;

const total = computed(() =>
  props.rows.reduce((sum, row) => sum + Number(row.value || 0), 0)
);

// A row can legitimately arrive without a label: a WhatsApp send that failed with no provider error string, or
// a skip with no recorded reason. The row is real and its count matters, so it is shown with a placeholder
// rather than dropped or rendered blank.
const visibleRows = computed(() =>
  props.rows.slice(0, VISIBLE_ROWS).map(row => ({
    ...row,
    key: row.id ?? 'unlabelled',
    name: row.label || t('ANALYTICS.BREAKDOWN.UNLABELLED'),
    share: total.value ? Math.round((row.value / total.value) * 100) : 0,
  }))
);

const remainingCount = computed(() =>
  Math.max(props.rows.length - VISIBLE_ROWS, 0)
);

const dimensionTabs = computed(() =>
  props.dimensions.map(value => ({
    label: t(`ANALYTICS.${props.scope}.BREAKDOWN.${value.toUpperCase()}`),
    value,
  }))
);

const activeDimensionIndex = computed(() =>
  Math.max(
    dimensionTabs.value.findIndex(tab => tab.value === props.dimension),
    0
  )
);
</script>

<template>
  <div
    class="flex flex-col gap-4 p-5 border rounded-overlay bg-n-solid-1 border-n-weak"
  >
    <div
      class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
    >
      <span class="text-heading-3 text-n-slate-12">{{ title }}</span>
      <TabBar
        v-if="dimensionTabs.length"
        :tabs="dimensionTabs"
        :initial-active-tab="activeDimensionIndex"
        @tab-changed="tab => emit('dimensionChange', tab.value)"
      />
    </div>
    <div v-if="loading" class="flex flex-col gap-3">
      <div
        v-for="n in 5"
        :key="n"
        class="w-full h-6 rounded bg-n-slate-3 animate-pulse"
      />
    </div>
    <div v-else-if="visibleRows.length" class="flex flex-col gap-3">
      <div
        v-for="row in visibleRows"
        :key="row.key"
        class="flex flex-col gap-1.5"
      >
        <div class="flex items-center justify-between gap-3 min-w-0">
          <span class="truncate text-body-main text-n-slate-11">
            {{ row.name }}
          </span>
          <span class="flex items-center gap-2 shrink-0">
            <span
              class="font-medium tabular-nums text-body-main text-n-slate-12"
            >
              {{ Number(row.value).toLocaleString() }}
            </span>
            <span class="tabular-nums text-label-small text-n-slate-10">
              {{ t('ANALYTICS.BREAKDOWN.SHARE', { value: row.share }) }}
            </span>
          </span>
        </div>
        <div class="w-full h-1.5 rounded-full bg-n-alpha-2">
          <div
            class="h-1.5 rounded-full bg-n-iris-9"
            :style="{ width: `${row.share}%` }"
          />
        </div>
      </div>
      <span v-if="remainingCount" class="text-label-small text-n-slate-10">
        {{ t('ANALYTICS.BREAKDOWN.REMAINING', { count: remainingCount }) }}
      </span>
    </div>
    <span v-else class="text-body-main text-n-slate-10">
      {{ t('ANALYTICS.NO_DATA') }}
    </span>
  </div>
</template>
