<script setup>
import { ref, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAutomation } from 'dashboard/composables/useAutomation';
import {
  audienceConditionFor,
  findSharedAudience,
} from 'dashboard/helper/audienceHelper';
import AutomationRuleForm from './AutomationRuleForm.vue';

const emit = defineEmits(['saveAutomation']);

const START_VALUE = {
  name: null,
  description: null,
  event_name: 'conversation_created',
  execution_delay: null,
  conditions: [
    {
      attribute_key: 'status',
      filter_operator: 'equal_to',
      values: '',
      query_operator: 'and',
      custom_attribute_type: '',
    },
  ],
  actions: [
    {
      action_name: 'assign_agent',
      action_params: [],
    },
  ],
};

const store = useStore();
const formRef = ref(null);
const contactViews = useMapGetter('customViews/getContactCustomViews');

const {
  automation,
  automationTypes,
  onEventChange,
  getConditionDropdownValues,
  appendNewCondition,
  appendNewAction,
  removeFilter,
  removeAction,
  resetAction,
  getActionDropdownValues,
  manifestCustomAttributes,
  manifestLynomiaConditions,
  loadLynomiaOptions,
} = useAutomation(START_VALUE);

/**
 * Opens the panel on a new rule.
 * @param {Object} [options] - Options.
 * @param {?number} [options.executionDelay] - Minutes to wait, for a delayed rule.
 * @param {?number} [options.audienceId] - A shared audience to start the rule's conditions from ("Use in a new
 *   automation rule", from the audience itself). An id that is not one of this account's shared audiences is
 *   ignored, so the panel simply opens on the usual blank condition.
 */
const open = async ({ executionDelay = null, audienceId = null } = {}) => {
  automation.value = structuredClone(START_VALUE);
  manifestCustomAttributes();
  manifestLynomiaConditions();
  formRef.value?.open(executionDelay);
  // Shared audiences and the Commerce options arrive after the panel opens.
  await loadLynomiaOptions();
  manifestLynomiaConditions();
  if (!audienceId) return;

  const audience = findSharedAudience(contactViews.value, audienceId);
  if (audience) automation.value.conditions = [audienceConditionFor(audience)];
};
const close = () => formRef.value?.close();

const onSave = (payload, mode) => {
  emit('saveAutomation', payload, mode);
};

onMounted(() => {
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');
  store.dispatch('contacts/get');
  store.dispatch('teams/get');
  store.dispatch('labels/get');
  store.dispatch('campaigns/get');
});

defineExpose({ open, close });
</script>

<template>
  <AutomationRuleForm
    ref="formRef"
    v-model:automation="automation"
    mode="create"
    :automation-types="automationTypes"
    :get-condition-dropdown-values="getConditionDropdownValues"
    :get-action-dropdown-values="getActionDropdownValues"
    :append-new-condition="appendNewCondition"
    :append-new-action="appendNewAction"
    :remove-filter="removeFilter"
    :remove-action="removeAction"
    :reset-action="resetAction"
    :on-event-change="onEventChange"
    @save="onSave"
  />
</template>
