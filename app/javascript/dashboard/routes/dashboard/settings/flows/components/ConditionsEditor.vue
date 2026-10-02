<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useAutomation } from 'dashboard/composables/useAutomation';
import { useEditableAutomation } from 'dashboard/composables/useEditableAutomation';
import { generateAutomationPayload } from 'dashboard/helper/automationHelper';
import { useConditionFilterTypes } from '../../automation/useConditionFilterTypes';

// A node's conditions are Lynomia Automation conditions (docs/flow-builder/04-node-contracts.md §conditions): the rule
// builder's own fields and condition rows, loaded and stored with Automation's own conversions, checked by Automation's
// validation on the server. `scope` narrows the fields for the Audience and Commerce condition nodes.
const props = defineProps({
  scope: {
    type: String,
    default: 'all',
    validator: value => ['all', 'audience', 'commerce'].includes(value),
  },
  optional: { type: Boolean, default: false },
});
const conditions = defineModel({ type: Array, default: () => [] });

const EVENT = 'conversation_updated';
const SCOPES = {
  all: () => true,
  audience: key => key === 'contact_audience',
  commerce: key => key.startsWith('commerce_'),
};

const {
  automationTypes,
  getConditionDropdownValues,
  manifestCustomAttributes,
  manifestLynomiaConditions,
  loadLynomiaOptions,
} = useAutomation();
const { formatAutomation } = useEditableAutomation();
const allCustomAttributes = useMapGetter('attributes/getAttributes');

const rows = ref([]);
const ready = ref(false);

const allFilterTypes = useConditionFilterTypes(
  automationTypes,
  EVENT,
  getConditionDropdownValues
);
const filterTypes = computed(() =>
  props.scope === 'all'
    ? allFilterTypes.value
    : allFilterTypes.value.filter(
        type => !type.disabled && SCOPES[props.scope](type.value)
      )
);

const newRow = () => {
  const [first] = filterTypes.value.filter(type => !type.disabled);
  const key = props.scope === 'all' ? 'status' : first?.value;
  const type = filterTypes.value.find(item => item.value === key);
  return {
    attribute_key: key,
    filter_operator: type?.filterOperators?.[0]?.value || 'equal_to',
    values: '',
    query_operator: 'and',
    custom_attribute_type: '',
  };
};

const toPayload = () => {
  if (!rows.value.length) return [];
  rows.value.forEach(condition => {
    const type = filterTypes.value.find(
      item => item.attributeKey === condition.attribute_key
    );
    condition.custom_attribute_type =
      type?.attributeModel && type.attributeModel !== 'standard'
        ? type.attributeModel
        : '';
  });
  return generateAutomationPayload({ conditions: rows.value, actions: [] })
    .conditions;
};

const addRow = () => {
  rows.value = [...rows.value, newRow()];
};

const removeRow = index => {
  rows.value = rows.value.filter((_, i) => i !== index);
};

onMounted(async () => {
  await loadLynomiaOptions();
  manifestCustomAttributes();
  manifestLynomiaConditions();
  rows.value = conditions.value.length
    ? formatAutomation(
        { event_name: EVENT, conditions: conditions.value, actions: [] },
        allCustomAttributes.value,
        automationTypes,
        []
      ).conditions
    : [];
  if (!rows.value.length && !props.optional) addRow();
  ready.value = true;
});

watch(
  rows,
  () => {
    if (ready.value) conditions.value = toPayload();
  },
  { deep: true }
);
</script>

<template>
  <ul
    class="grid gap-3 p-3 m-0 list-none outline outline-1 rounded-xl -outline-offset-1 outline-n-weak"
  >
    <template v-for="(condition, i) in rows" :key="i">
      <ConditionRow
        v-if="i === 0"
        v-model:attribute-key="rows[i].attribute_key"
        v-model:filter-operator="rows[i].filter_operator"
        v-model:values="rows[i].values"
        :filter-types="filterTypes"
        :show-query-operator="false"
        @remove="removeRow(i)"
      />
      <ConditionRow
        v-else
        v-model:attribute-key="rows[i].attribute_key"
        v-model:filter-operator="rows[i].filter_operator"
        v-model:query-operator="rows[i - 1].query_operator"
        v-model:values="rows[i].values"
        :filter-types="filterTypes"
        show-query-operator
        @remove="removeRow(i)"
      />
    </template>
    <div>
      <NextButton
        icon="i-lucide-plus"
        blue
        faded
        sm
        :label="$t('FLOW_BUILDER.CONFIG.ADD_CONDITION')"
        @click="addRow"
      />
    </div>
  </ul>
</template>
