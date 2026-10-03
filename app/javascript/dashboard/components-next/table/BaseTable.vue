<script setup>
import { computed } from 'vue';
import { Skeleton } from 'dashboard/components-next/skeleton';

const props = defineProps({
  headers: {
    type: Array,
    default: () => [],
  },
  items: {
    type: Array,
    default: () => [],
  },
  noDataMessage: {
    type: String,
    default: '',
  },
  loading: {
    type: Boolean,
    default: false,
  },
  // Column keys the table can be sorted by, in the same order as `headers`. An entry of `null` marks a
  // column that cannot be sorted, so the array stays index-aligned with the headers it describes.
  sortableColumns: {
    type: Array,
    default: () => [],
  },
  sortBy: {
    type: String,
    default: '',
  },
  sortOrder: {
    type: String,
    default: 'asc',
    validator: value => ['asc', 'desc'].includes(value),
  },
  // Keeps the column headings in view while a long list scrolls underneath.
  stickyHeader: {
    type: Boolean,
    default: false,
  },
  // How many placeholder rows to draw while `loading`.
  loadingRows: {
    type: Number,
    default: 5,
  },
  // Confines a too-wide table to its container and scrolls it, instead of letting the columns spill
  // past the card. Off by default: on a phone it trades a control that is visible-but-escaping for one
  // that needs a horizontal swipe, and that trade belongs with the sticky action column designed in the
  // responsive phase, not here.
  scrollable: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['sort']);

const SORT_ICONS = {
  none: 'i-lucide-chevrons-up-down',
  asc: 'i-lucide-chevron-up',
  desc: 'i-lucide-chevron-down',
};

// The headings stay in the empty state: a table with no rows still has to say what its columns were.
const showHeaders = computed(() => props.headers.length > 0);
const columnCount = computed(() => props.headers.length || 1);

const sortKeyFor = index => props.sortableColumns[index] || null;

const sortStateFor = index => {
  const key = sortKeyFor(index);
  if (!key || key !== props.sortBy) return 'none';
  return props.sortOrder;
};

const toggleSort = index => {
  const key = sortKeyFor(index);
  if (!key) return;
  const order =
    key === props.sortBy && props.sortOrder === 'asc' ? 'desc' : 'asc';
  emit('sort', { key, order });
};
</script>

<template>
  <div class="w-full" :class="{ 'overflow-x-auto': scrollable }">
    <table class="min-w-full table-auto divide-y divide-n-weak">
      <thead
        v-if="showHeaders"
        class="border-t border-n-weak"
        :class="{ 'sticky top-0 z-sticky bg-n-surface-1': stickyHeader }"
      >
        <tr>
          <th
            v-for="(header, index) in headers"
            :key="index"
            class="py-4 ltr:pr-4 rtl:pl-4 text-start text-heading-3 text-n-slate-12 capitalize"
            :aria-sort="
              sortStateFor(index) === 'none'
                ? null
                : sortStateFor(index) === 'asc'
                  ? 'ascending'
                  : 'descending'
            "
          >
            <button
              v-if="sortKeyFor(index)"
              type="button"
              class="inline-flex items-center gap-1 p-0 m-0 bg-transparent border-0 text-heading-3 text-n-slate-12 capitalize hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand rounded-sm"
              :aria-label="$t('TABLE.SORT_BY', { column: header })"
              @click="toggleSort(index)"
            >
              <slot :name="`header-${index}`" :header="header">
                {{ header }}
              </slot>
              <span
                class="size-4 shrink-0"
                :class="[
                  SORT_ICONS[sortStateFor(index)],
                  sortStateFor(index) === 'none'
                    ? 'text-n-slate-10'
                    : 'text-n-slate-12',
                ]"
              />
            </button>
            <slot v-else :name="`header-${index}`" :header="header">
              {{ header }}
            </slot>
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak text-n-slate-11">
        <template v-if="loading">
          <tr
            v-for="row in loadingRows"
            :key="`skeleton-${row}`"
            aria-hidden="true"
          >
            <td
              v-for="column in columnCount"
              :key="column"
              class="py-3 ltr:pr-4 rtl:pl-4"
            >
              <Skeleton :width="column === 1 ? 'w-40' : 'w-24'" />
            </td>
          </tr>
        </template>
        <template v-else-if="items.length">
          <slot name="row" :items="items" />
        </template>
        <tr v-else-if="noDataMessage">
          <td
            :colspan="columnCount"
            class="py-20 text-center text-body-main !text-base text-n-slate-11"
          >
            {{ noDataMessage }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
