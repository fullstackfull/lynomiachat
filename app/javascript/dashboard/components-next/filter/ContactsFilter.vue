<script setup>
import { useTemplateRef, onBeforeUnmount, onMounted, computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import { useTrack } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { vOnClickOutside } from '@vueuse/components';
import { CONTACTS_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import { useContactFilterContext } from './contactProvider.js';
import {
  useAudienceFilterTypes,
  COMMERCE_ORDER_KEY,
} from './audienceProvider.js';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';

import Button from 'next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ConditionRow from './ConditionRow.vue';

const props = defineProps({
  isSegmentView: { type: Boolean, default: false },
  segmentName: { type: String, default: '' },
  // Lynomia shared audiences (docs/automation/02-shared-audiences.md).
  sharedSegment: { type: Boolean, default: false },
  activeRuleCount: { type: Number, default: 0 },
  // Lynomia Campaigns: campaigns still to send that use it (docs/campaigns/03-audience-dependency.md).
  campaignCount: { type: Number, default: 0 },
});

const emit = defineEmits([
  'applyFilter',
  'updateSegment',
  'close',
  'clearFilters',
]);
const { attributeFilterTypes } = useContactFilterContext();
const { loadAudienceFields, unreadContacts } = useAudienceFilterTypes();

const filters = defineModel({
  type: Array,
  default: [],
});
const segmentNameLocal = ref(props.segmentName);

const DEFAULT_FILTER = {
  attributeKey: 'name',
  filterOperator: 'equal_to',
  values: '',
  queryOperator: 'and',
  attributeModel: 'standard',
};

const { t } = useI18n();
const { installationName } = useBranding();
const store = useStore();

const resetFilter = () => {
  emit('clearFilters');
  filters.value = [{ ...DEFAULT_FILTER }];
};

const removeFilter = index => {
  if (filters.value.length === 1) {
    resetFilter();
  } else {
    filters.value.splice(index, 1);
  }
};

const addFilter = () => {
  filters.value.push({ ...DEFAULT_FILTER });
};

const conditionsRef = useTemplateRef('conditionsRef');

const isConditionsValid = () => {
  return conditionsRef.value.every(condition => condition.validate());
};

const updateSavedSegment = () => {
  if (isConditionsValid()) {
    emit('updateSegment', filters.value, segmentNameLocal.value);
  }
};

function validateAndSubmit() {
  if (!isConditionsValid()) return;

  store.dispatch(
    'contacts/setContactFilters',
    useSnakeCase(JSON.parse(JSON.stringify(filters.value)))
  );
  emit('applyFilter', filters.value);
  useTrack(CONTACTS_EVENTS.APPLY_FILTER, {
    appliedFilters: filters.value.map(filter => ({
      key: filter.attributeKey,
      operator: filter.filterOperator,
      queryOperator: filter.queryOperator,
    })),
  });
}

// What the conversation and Commerce conditions mean, shown while they are used (docs/audience/02).
const usesKey = test =>
  filters.value.some(filter => test(filter.attributeKey || ''));
const usesConversation = computed(() =>
  usesKey(key => key.startsWith('conversation_'))
);
const usesCommerce = computed(() =>
  usesKey(key => key.startsWith('commerce_'))
);
const unreadNote = computed(() =>
  usesKey(key => COMMERCE_ORDER_KEY.test(key)) && unreadContacts.value > 0
    ? t('CONTACTS_FILTER.AUDIENCE.UNREAD', { count: unreadContacts.value })
    : ''
);

onMounted(() => loadAudienceFields());

// Members open a shared audience read-only; administrators are told when rules or campaigns depend on it.
const isUsed = computed(() => props.activeRuleCount + props.campaignCount > 0);
const sharedNote = computed(() => {
  if (!props.isSegmentView)
    return t('CONTACTS_FILTER.AUDIENCE.SHARED.READ_ONLY');
  if (isUsed.value) {
    return t('CONTACTS_FILTER.AUDIENCE.SHARED.USED_BY', {
      rules: props.activeRuleCount,
      campaigns: props.campaignCount,
    });
  }
  return t('CONTACTS_FILTER.AUDIENCE.SHARED.EDIT');
});

const filterModalHeaderTitle = computed(() => {
  return !props.isSegmentView
    ? t('CONTACTS_LAYOUT.FILTER.TITLE')
    : t('CONTACTS_LAYOUT.FILTER.EDIT_SEGMENT');
});

onBeforeUnmount(() => emit('close'));
const outsideClickHandler = [
  () => emit('close'),
  { ignore: ['#toggleContactsFilterButton'] },
];
</script>

<template>
  <div
    v-on-click-outside="outsideClickHandler"
    role="group"
    :aria-label="filterModalHeaderTitle"
    class="z-dropdown w-full sm:w-[min(34rem,calc(100vw-2rem))] lg:w-[46.875rem] overflow-visible border border-n-weak bg-n-alpha-3 backdrop-blur-panel shadow-overlay rounded-overlay p-6 grid gap-6"
    @keydown.esc="emit('close')"
  >
    <h3 class="text-base font-medium leading-6 text-n-slate-12">
      {{ filterModalHeaderTitle }}
    </h3>
    <div v-if="props.isSegmentView">
      <div class="pb-6 border-b border-n-weak">
        <Input
          v-model="segmentNameLocal"
          :label="$t('CONTACTS_LAYOUT.FILTER.SEGMENT.LABEL')"
          :placeholder="t('CONTACTS_LAYOUT.FILTER.SEGMENT.INPUT_PLACEHOLDER')"
        />
      </div>
    </div>
    <ul class="grid gap-4 list-none min-w-0">
      <template v-for="(filter, index) in filters" :key="filter.id">
        <ConditionRow
          v-if="index === 0"
          ref="conditionsRef"
          :key="`filter-${filter.attributeKey}-0`"
          v-model:attribute-key="filter.attributeKey"
          v-model:filter-operator="filter.filterOperator"
          v-model:values="filter.values"
          :filter-types="attributeFilterTypes"
          :show-query-operator="false"
          @remove="removeFilter(index)"
        />
        <ConditionRow
          v-else
          :key="`filter-${filter.attributeKey}-${index}`"
          ref="conditionsRef"
          v-model:attribute-key="filter.attributeKey"
          v-model:filter-operator="filter.filterOperator"
          v-model:query-operator="filters[index - 1].queryOperator"
          v-model:values="filter.values"
          show-query-operator
          :filter-types="attributeFilterTypes"
          @remove="removeFilter(index)"
        />
      </template>
    </ul>
    <p
      v-if="sharedSegment"
      class="rounded-lg px-3 py-2 text-label-small"
      :class="
        isSegmentView && isUsed
          ? 'bg-n-amber-2 text-n-amber-11'
          : 'bg-n-alpha-2 text-n-slate-11'
      "
      data-test-id="shared-audience-note"
    >
      {{ sharedNote }}
    </p>
    <div
      v-if="usesConversation || usesCommerce"
      class="flex flex-col gap-1 text-label-small text-n-slate-11"
      data-test-id="audience-notes"
    >
      <p v-if="usesConversation">
        {{ t('CONTACTS_FILTER.AUDIENCE.CONVERSATION_NOTE') }}
      </p>
      <p v-if="usesCommerce">
        {{ t('CONTACTS_FILTER.AUDIENCE.COMMERCE_NOTE', { installationName }) }}
      </p>
      <p
        v-if="unreadNote"
        class="rounded-lg bg-n-amber-2 px-3 py-2 text-n-amber-11"
        data-test-id="audience-unread"
      >
        {{ unreadNote }}
      </p>
    </div>
    <div class="flex flex-wrap justify-between gap-2">
      <Button sm ghost blue class="flex-shrink-0" @click="addFilter">
        {{ $t('CONTACTS_LAYOUT.FILTER.BUTTONS.ADD_FILTER') }}
      </Button>
      <div class="flex gap-2 flex-shrink-0">
        <Button sm faded slate @click="resetFilter">
          {{ $t('CONTACTS_LAYOUT.FILTER.BUTTONS.CLEAR_FILTERS') }}
        </Button>
        <Button
          v-if="isSegmentView"
          sm
          solid
          blue
          :disabled="!segmentNameLocal"
          @click="updateSavedSegment"
        >
          {{ $t('CONTACTS_LAYOUT.FILTER.BUTTONS.UPDATE_SEGMENT') }}
        </Button>
        <Button v-else sm solid blue @click="validateAndSubmit">
          {{ $t('CONTACTS_LAYOUT.FILTER.BUTTONS.APPLY_FILTERS') }}
        </Button>
      </div>
    </div>
  </div>
</template>
