<script setup>
// The account-specific values one recipe needs (docs/usability/10-recipe-architecture.md §wizard). Every option list
// is the current account's own: its teams, labels, shared audiences, connected stores, the currencies its orders have
// actually used, the Commerce events the engine really has. Nothing is typed in by id, and nothing destructive or
// financial is ever preselected.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import { INPUT_TYPES } from 'dashboard/recipes';
import { COMMERCE_EVENTS } from 'dashboard/routes/dashboard/settings/automation/lynomiaAutomation';

const props = defineProps({
  inputs: { type: Array, required: true },
  context: { type: Object, required: true },
  errors: { type: Object, default: () => ({}) },
});

const values = defineModel({ type: Object, required: true });

const { t } = useI18n();

const PRIORITIES = ['low', 'medium', 'high', 'urgent'];
const LANGUAGES = ['ar', 'en', 'both'];

const named = list => list.map(({ id, name }) => ({ value: id, label: name }));

const optionsFor = input => {
  switch (input.type) {
    case INPUT_TYPES.TEAM:
      return named(props.context.teams);
    case INPUT_TYPES.AUDIENCE:
      return named(props.context.audiences);
    case INPUT_TYPES.STORE:
      return named(props.context.stores);
    case INPUT_TYPES.CURRENCY:
      return props.context.currencies.map(currency => ({
        value: currency,
        label: currency,
      }));
    case INPUT_TYPES.PRIORITY:
      return PRIORITIES.map(priority => ({
        value: priority,
        label: t(`CONVERSATION.PRIORITY.OPTIONS.${priority.toUpperCase()}`),
      }));
    case INPUT_TYPES.LANGUAGE:
      return LANGUAGES.map(language => ({
        value: language,
        label: t(`RECIPES.LANGUAGES.${language.toUpperCase()}`),
      }));
    case INPUT_TYPES.COMMERCE_EVENT:
      return COMMERCE_EVENTS.map(event => ({
        value: event,
        label: t(`AUTOMATION.EVENTS.${event.toUpperCase()}`),
      }));
    default:
      return [];
  }
};

const labelOptions = computed(() =>
  props.context.labels.map(({ title }) => ({ value: title, label: title }))
);

const isSelect = input =>
  [
    INPUT_TYPES.TEAM,
    INPUT_TYPES.AUDIENCE,
    INPUT_TYPES.STORE,
    INPUT_TYPES.CURRENCY,
    INPUT_TYPES.PRIORITY,
    INPUT_TYPES.LANGUAGE,
    INPUT_TYPES.COMMERCE_EVENT,
  ].includes(input.type);

const labelFor = input => t(`RECIPES.INPUTS.${input.key.toUpperCase()}`);

const hintFor = input => (input.required ? '' : t('RECIPES.INPUTS.OPTIONAL'));

const boundary = value => (value === undefined ? '' : String(value));
</script>

<template>
  <div class="flex flex-col gap-4">
    <div
      v-for="input in inputs"
      :key="input.key"
      class="flex flex-col gap-1"
      :data-test-id="`recipe-input-${input.key}`"
    >
      <span class="text-label-small text-n-slate-11">
        {{ labelFor(input) }}
        <span v-if="hintFor(input)" class="text-n-slate-10">
          {{ hintFor(input) }}
        </span>
      </span>

      <Select
        v-if="isSelect(input)"
        v-model="values[input.key]"
        :options="optionsFor(input)"
        :placeholder="t('RECIPES.INPUTS.CHOOSE')"
        :aria-label="labelFor(input)"
        :error="errors[input.key] || ''"
      />
      <TagMultiSelectComboBox
        v-else-if="input.type === INPUT_TYPES.LABELS"
        v-model="values[input.key]"
        :options="labelOptions"
        :placeholder="t('RECIPES.INPUTS.CHOOSE')"
        :empty-state="t('RECIPES.INPUTS.NO_LABELS')"
        :has-error="Boolean(errors[input.key])"
        class="[&>div>button]:bg-n-alpha-black2"
      />
      <Input
        v-else-if="input.type === INPUT_TYPES.NUMBER"
        v-model="values[input.key]"
        type="number"
        :min="boundary(input.min)"
        :max="boundary(input.max)"
        :aria-label="labelFor(input)"
        :message="errors[input.key] || ''"
        :message-type="errors[input.key] ? 'error' : 'info'"
      />
      <Input
        v-else
        v-model="values[input.key]"
        type="url"
        :placeholder="t('RECIPES.INPUTS.URL_PLACEHOLDER')"
        :aria-label="labelFor(input)"
        :message="errors[input.key] || ''"
        :message-type="errors[input.key] ? 'error' : 'info'"
      />
    </div>
  </div>
</template>
