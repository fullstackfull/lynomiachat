<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';

import ActiveFilterPreview from 'dashboard/components-next/filter/ActiveFilterPreview.vue';
import {
  useAudienceFilterTypes,
  audienceValuesForEdit,
} from 'dashboard/components-next/filter/audienceProvider.js';

const props = defineProps({
  activeSegment: { type: Object, default: null },
});

const emit = defineEmits(['clearFilters', 'openFilter']);

const { t } = useI18n();
const route = useRoute();

const appliedFilters = useMapGetter('contacts/getAppliedContactFiltersV4');
const { audienceFilterTypes } = useAudienceFilterTypes();
const activeSegmentId = computed(() => route.params.segmentId);

const activeSegmentQuery = computed(() => {
  const query = props.activeSegment?.query?.payload;
  if (!Array.isArray(query)) return [];

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values: transformed.values,
    };
  });

  return newFilters;
});

const hasActiveSegments = computed(
  () => props.activeSegment && activeSegmentId.value !== 0
);

// Conversation and Commerce conditions (Lynomia Audience) show their field's name and their options' names.
const withAudienceNames = filter => {
  const type = audienceFilterTypes.value.find(
    item => item.attributeKey === filter.attributeKey
  );
  if (!type) return filter;

  const values = Array.isArray(filter.values)
    ? audienceValuesForEdit(
        type,
        filter.values.map(value => value?.id ?? value)
      )
    : filter.values;
  return { ...filter, attributeName: type.attributeName, values };
};

const activeFilterQueryData = computed(() => {
  const filters = hasActiveSegments.value
    ? activeSegmentQuery.value
    : appliedFilters.value;
  return filters.map(withAudienceNames);
});
</script>

<template>
  <ActiveFilterPreview
    :applied-filters="activeFilterQueryData"
    :max-visible-filters="2"
    :more-filters-label="
      t('CONTACTS_LAYOUT.FILTER.ACTIVE_FILTERS.MORE_FILTERS', {
        count: activeFilterQueryData.length - 2,
      })
    "
    :clear-button-label="
      t('CONTACTS_LAYOUT.FILTER.ACTIVE_FILTERS.CLEAR_FILTERS')
    "
    :show-clear-button="!hasActiveSegments"
    class="max-w-5xl"
    @open-filter="emit('openFilter')"
    @clear-filters="emit('clearFilters')"
  />
</template>
