<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import BulkSelectBar from 'dashboard/components-next/captain/assistant/BulkSelectBar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BulkLabelActions from 'dashboard/components/widgets/conversation/conversationBulkActions/BulkLabelActions.vue';
import Policy from 'dashboard/components/policy.vue';

const props = defineProps({
  visibleContactIds: {
    type: Array,
    default: () => [],
  },
  selectedContactIds: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  // Everything the current view matches, not only what is on screen.
  totalCount: {
    type: Number,
    default: 0,
  },
  isWholeViewSelected: {
    type: Boolean,
    default: false,
  },
  // The search endpoint reports the page size as its count, by design: search is an unindexed ILIKE over four
  // columns and a COUNT on that hot path is the thing `has_more` exists to avoid. So "is there more" is a
  // separate signal from "how much more", and only the first one is always available.
  hasMore: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'clearSelection',
  'assignLabels',
  'removeLabels',
  'toggleAll',
  'selectAllMatching',
  'deleteSelected',
]);

const { t } = useI18n();

const selectedCount = computed(() => props.selectedContactIds.length);
const totalVisibleContacts = computed(() => props.visibleContactIds.length);

const selectAllLabel = computed(() => {
  if (!totalVisibleContacts.value) {
    return '';
  }

  return t('CONTACTS_BULK_ACTIONS.SELECT_ALL', {
    count: totalVisibleContacts.value,
  });
});

// True only when the server gave a total that means anything beyond this page.
const hasUsableTotal = computed(
  () => props.totalCount > totalVisibleContacts.value
);

const selectedCountLabel = computed(() => {
  if (!props.isWholeViewSelected) {
    return t('CONTACTS_BULK_ACTIONS.SELECTED_COUNT', {
      count: selectedCount.value,
    });
  }
  return hasUsableTotal.value
    ? t('CONTACTS_BULK_ACTIONS.SELECTED_ALL_MATCHING_COUNT', {
        count: props.totalCount,
      })
    : t('CONTACTS_BULK_ACTIONS.SELECTED_ALL_MATCHING');
});

// Offered once the page itself is exhausted, which is the moment "select all" stops meaning what it says: the
// view has more rows than the browser is holding, and only the server can enumerate them.
//
// `hasMore` is what makes this reachable on a search view. Gating on the total alone meant the whole feature was
// silently off there, because search's total IS the page size
// (docs/product-enablement/12-proposed-phases.md D6).
const canSelectAllMatching = computed(
  () =>
    !props.isWholeViewSelected &&
    totalVisibleContacts.value > 0 &&
    (hasUsableTotal.value || props.hasMore) &&
    selectedCount.value >= totalVisibleContacts.value
);

// No number is shown when the server did not give one. Inventing one, or showing the page size, would both be
// lies about what the action is going to do.
const selectAllMatchingLabel = computed(() =>
  hasUsableTotal.value
    ? t('CONTACTS_BULK_ACTIONS.SELECT_ALL_MATCHING', {
        count: props.totalCount,
      })
    : t('CONTACTS_BULK_ACTIONS.SELECT_ALL_MATCHING_UNCOUNTED')
);

const allItems = computed(() =>
  props.visibleContactIds.map(id => ({
    id,
  }))
);

const selectionModel = computed({
  get: () => new Set(props.selectedContactIds),
  set: newSet => {
    if (!props.visibleContactIds.length) {
      emit('toggleAll', false);
      return;
    }

    const shouldSelectAll = props.visibleContactIds.every(id => newSet.has(id));
    emit('toggleAll', shouldSelectAll);
  },
});

const handleAssignLabels = labels => {
  emit('assignLabels', labels);
};

const handleRemoveLabels = labels => {
  emit('removeLabels', labels);
};
</script>

<template>
  <div
    class="sticky top-0 z-10 bg-gradient-to-b from-n-surface-1 from-90% to-transparent pt-1 pb-2"
  >
    <BulkSelectBar
      v-model="selectionModel"
      :all-items="allItems"
      :select-all-label="selectAllLabel"
      :selected-count-label="selectedCountLabel"
      class="py-2 ltr:!pr-3 rtl:!pl-3 justify-between"
    >
      <template #primaryActions>
        <Button
          v-if="canSelectAllMatching"
          sm
          ghost
          blue
          :label="selectAllMatchingLabel"
          class="!px-1"
          @click="emit('selectAllMatching')"
        />
        <Button
          sm
          ghost
          slate
          :label="t('CONTACTS_BULK_ACTIONS.CLEAR_SELECTION')"
          class="!px-1"
          @click="emit('clearSelection')"
        />
      </template>
      <template #actions>
        <div class="flex items-center gap-2 ms-auto">
          <BulkLabelActions
            type="contact"
            :is-loading="isLoading"
            :disabled="!selectedCount"
            @assign="handleAssignLabels"
          />
          <BulkLabelActions
            type="contact"
            action="remove"
            :is-loading="isLoading"
            :disabled="!selectedCount"
            @remove="handleRemoveLabels"
          />
          <div class="w-px h-3 bg-n-weak rounded-lg" />
          <Policy :permissions="['administrator']">
            <Button
              v-tooltip.bottom="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              sm
              ghost
              ruby
              icon="i-lucide-trash"
              :label="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              :aria-label="t('CONTACTS_BULK_ACTIONS.DELETE_CONTACTS')"
              :disabled="!selectedCount || isLoading"
              :is-loading="isLoading"
              class="!px-2 [&>span:nth-child(2)]:hidden md:[&>span:nth-child(2)]:inline-flex"
              @click="emit('deleteSelected')"
            />
          </Policy>
        </div>
      </template>
    </BulkSelectBar>
  </div>
</template>
