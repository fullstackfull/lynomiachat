<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ConditionsEditor from './ConditionsEditor.vue';
import OptionsEditor from './OptionsEditor.vue';
import { NODE_ICONS } from '../flowGraph';

// The selected node's settings (docs/flow-builder/04-node-contracts.md). Lists come from the account's own labels,
// teams, agents and custom attributes; limits from the channel capabilities the server sends. The server validates
// everything again on save and publish.
const props = defineProps({
  node: { type: Object, required: true },
  nodes: { type: Array, required: true },
  capabilities: { type: Object, required: true },
  variables: { type: Array, default: () => [] },
  // This node's server validation errors, already worded.
  errors: { type: Array, default: () => [] },
});
const emit = defineEmits(['update', 'delete', 'duplicate', 'close']);

const { t } = useI18n();
const labels = useMapGetter('labels/getLabels');
const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getVerifiedAgents');
const attributesByModel = useMapGetter('attributes/getAttributesByModel');

const type = computed(() => props.node.data.type);
const data = computed(() => props.node.data.data || {});
const set = (key, value) => emit('update', { ...data.value, [key]: value });
const setMany = values => emit('update', { ...data.value, ...values });

const textLimit = computed(() =>
  ['buttons', 'list'].includes(type.value)
    ? props.capabilities[type.value].body
    : props.capabilities.text.body
);

const labelOptions = computed(() =>
  labels.value.map(label => ({ value: label.title, label: label.title }))
);
const teamOptions = computed(() =>
  teams.value.map(team => ({ value: team.id, label: team.name }))
);
const agentOptions = computed(() =>
  agents.value.map(agent => ({ value: agent.id, label: agent.name }))
);
const attributeOptions = model =>
  attributesByModel.value(model).map(attr => ({
    value: attr.attribute_key,
    label: attr.attribute_display_name,
  }));
const targetOptions = computed(() =>
  props.nodes
    .filter(item => item.id !== props.node.id && item.data.type !== 'start')
    .map(item => ({
      value: item.id,
      label: `${t(`FLOW_BUILDER.NODES.${item.data.type.toUpperCase()}`)} · ${item.id}`,
    }))
);
const replyTypes = ['any', 'number', 'email', 'phone', 'keywords'].map(
  value => ({
    value,
    label: t(`FLOW_BUILDER.CONFIG.REPLY_TYPES.${value.toUpperCase()}`),
  })
);
const storeScopes = ['', 'context', 'contact', 'conversation'].map(value => ({
  value,
  label: t(
    `FLOW_BUILDER.CONFIG.STORE_SCOPES.${(value || 'none').toUpperCase()}`
  ),
}));
const priorities = ['', 'low', 'medium', 'high', 'urgent'].map(value => ({
  value,
  label: t(`FLOW_BUILDER.CONFIG.PRIORITIES.${(value || 'none').toUpperCase()}`),
}));
const lookupModes = ['latest_order', 'order_number'].map(value => ({
  value,
  label: t(`FLOW_BUILDER.CONFIG.LOOKUP_MODES.${value.toUpperCase()}`),
}));
const variableOptions = computed(() =>
  props.variables.map(name => ({ value: name, label: `{{${name}}}` }))
);

const STORE_MODELS = {
  contact: 'contact_attribute',
  conversation: 'conversation_attribute',
};
const storeAs = computed(() => data.value.store_as || {});
const setStore = (key, value) => {
  const next = { ...storeAs.value, [key]: value };
  if (key === 'scope') next.key = '';
  set('store_as', next.scope ? next : undefined);
};

const appendVariable = (field, name) => {
  if (!name) return;
  set(field, `${data.value[field] || ''}{{${name}}}`);
};

const conditionScope = computed(
  () =>
    ({ audience_condition: 'audience', commerce_condition: 'commerce' })[
      type.value
    ] || 'all'
);
const hasConditions = computed(() =>
  ['condition', 'audience_condition', 'commerce_condition'].includes(type.value)
);
const attributeModel = computed(
  () =>
    ({
      set_contact_attribute: 'contact_attribute',
      set_conversation_attribute: 'conversation_attribute',
    })[type.value]
);
</script>

<template>
  <aside
    class="absolute inset-0 z-10 flex flex-col w-full md:static md:w-96 shrink-0 border-s border-n-weak bg-n-solid-1 overflow-hidden"
    data-test-id="flow-config-panel"
  >
    <header
      class="flex items-center gap-2 px-4 py-3 border-b border-n-weak shrink-0"
    >
      <Icon :icon="NODE_ICONS[type]" class="size-4 text-n-slate-11" />
      <h2 class="flex-1 m-0 text-sm font-medium text-n-slate-12 truncate">
        {{ t(`FLOW_BUILDER.NODES.${type.toUpperCase()}`) }}
      </h2>
      <NextButton
        v-if="type !== 'start'"
        v-tooltip.top="t('FLOW_BUILDER.CONFIG.DUPLICATE')"
        icon="i-lucide-copy"
        slate
        ghost
        sm
        @click="emit('duplicate')"
      />
      <NextButton
        v-if="type !== 'start'"
        v-tooltip.top="t('FLOW_BUILDER.CONFIG.DELETE')"
        icon="i-lucide-trash-2"
        ruby
        ghost
        sm
        data-test-id="flow-node-delete"
        @click="emit('delete')"
      />
      <NextButton icon="i-lucide-x" slate ghost sm @click="emit('close')" />
    </header>

    <div class="flex flex-col gap-4 p-4 overflow-y-auto">
      <ul
        v-if="errors.length"
        class="flex flex-col gap-1 p-3 m-0 list-none rounded-lg bg-n-ruby-2 text-sm text-n-ruby-11"
      >
        <li v-for="(message, index) in errors" :key="index">
          {{ message }}
        </li>
      </ul>

      <template v-if="type === 'start'">
        <p class="m-0 text-sm text-n-slate-11">
          {{ t('FLOW_BUILDER.CONFIG.START_HINT') }}
        </p>
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('FLOW_BUILDER.CONFIG.KEYWORDS') }}
          <TagInput
            :model-value="data.keywords || []"
            :placeholder="t('FLOW_BUILDER.CONFIG.KEYWORDS_PLACEHOLDER')"
            :auto-open-dropdown="false"
            class="px-2 py-1 rounded-lg outline outline-1 outline-n-weak"
            @update:model-value="set('keywords', $event)"
          />
        </label>
        <div class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('FLOW_BUILDER.CONFIG.START_CONDITIONS') }}
          <ConditionsEditor
            :key="node.id"
            :model-value="data.conditions || []"
            optional
            @update:model-value="set('conditions', $event)"
          />
        </div>
      </template>

      <template
        v-if="['send_message', 'question', 'buttons', 'list'].includes(type)"
      >
        <TextArea
          :model-value="data.text || ''"
          :label="t('FLOW_BUILDER.CONFIG.TEXT')"
          :max-length="textLimit"
          show-character-count
          auto-height
          data-test-id="flow-config-text"
          @update:model-value="set('text', $event)"
        />
        <Select
          model-value=""
          :options="variableOptions"
          :placeholder="t('FLOW_BUILDER.CONFIG.INSERT_VARIABLE')"
          @update:model-value="appendVariable('text', $event)"
        />
      </template>

      <template v-if="type === 'question'">
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('FLOW_BUILDER.CONFIG.REPLY_TYPE') }}
          <Select
            :model-value="data.reply_type || 'any'"
            :options="replyTypes"
            @update:model-value="set('reply_type', $event)"
          />
        </label>
        <label
          v-if="data.reply_type === 'keywords'"
          class="flex flex-col gap-1 text-sm text-n-slate-12"
        >
          {{ t('FLOW_BUILDER.CONFIG.ACCEPTED_WORDS') }}
          <TagInput
            :model-value="data.keywords || []"
            :auto-open-dropdown="false"
            class="px-2 py-1 rounded-lg outline outline-1 outline-n-weak"
            @update:model-value="set('keywords', $event)"
          />
        </label>
        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('FLOW_BUILDER.CONFIG.STORE_AS') }}
          <Select
            :model-value="storeAs.scope || ''"
            :options="storeScopes"
            @update:model-value="setStore('scope', $event)"
          />
        </label>
        <Input
          v-if="storeAs.scope === 'context'"
          :model-value="storeAs.key || ''"
          :label="t('FLOW_BUILDER.CONFIG.CONTEXT_KEY')"
          placeholder="order_no"
          @update:model-value="setStore('key', $event)"
        />
        <ComboBox
          v-else-if="storeAs.scope"
          :model-value="storeAs.key || ''"
          :options="attributeOptions(STORE_MODELS[storeAs.scope])"
          :placeholder="t('FLOW_BUILDER.CONFIG.ATTRIBUTE')"
          @update:model-value="setStore('key', $event)"
        />
        <div class="grid grid-cols-2 gap-2">
          <Input
            :model-value="data.max_attempts ?? 3"
            type="number"
            min="1"
            max="5"
            :label="t('FLOW_BUILDER.CONFIG.MAX_ATTEMPTS')"
            @update:model-value="set('max_attempts', Number($event))"
          />
          <Input
            :model-value="data.timeout_minutes ?? ''"
            type="number"
            min="1"
            max="1440"
            :label="t('FLOW_BUILDER.CONFIG.TIMEOUT_MINUTES')"
            @update:model-value="
              set('timeout_minutes', $event === '' ? undefined : Number($event))
            "
          />
        </div>
        <TextArea
          :model-value="data.retry_text || ''"
          :label="t('FLOW_BUILDER.CONFIG.RETRY_TEXT')"
          :max-length="capabilities.text.body"
          auto-height
          @update:model-value="set('retry_text', $event || undefined)"
        />
      </template>

      <template v-if="['buttons', 'list'].includes(type)">
        <Input
          v-if="type === 'list'"
          :model-value="data.button_label || ''"
          :label="t('FLOW_BUILDER.CONFIG.LIST_BUTTON')"
          :message="
            t('FLOW_BUILDER.CONFIG.MAX_CHARS', { n: capabilities.list.button })
          "
          @update:model-value="set('button_label', $event || undefined)"
        />
        <div class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ t('FLOW_BUILDER.CONFIG.OPTIONS') }}
          <OptionsEditor
            :model-value="data.options || []"
            :limits="capabilities[type]"
            :with-description="type === 'list'"
            @update:model-value="set('options', $event)"
          />
        </div>
        <Input
          :model-value="data.timeout_minutes ?? ''"
          type="number"
          min="1"
          max="1440"
          :label="t('FLOW_BUILDER.CONFIG.TIMEOUT_MINUTES')"
          @update:model-value="
            set('timeout_minutes', $event === '' ? undefined : Number($event))
          "
        />
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('FLOW_BUILDER.CONFIG.CHOICE_HINT') }}
        </p>
      </template>

      <div
        v-if="hasConditions"
        class="flex flex-col gap-1 text-sm text-n-slate-12"
      >
        {{ t('FLOW_BUILDER.CONFIG.CONDITIONS') }}
        <ConditionsEditor
          :key="node.id"
          :model-value="data.conditions || []"
          :scope="conditionScope"
          @update:model-value="set('conditions', $event)"
        />
      </div>

      <template v-if="attributeModel">
        <ComboBox
          :model-value="data.key || ''"
          :options="attributeOptions(attributeModel)"
          :placeholder="t('FLOW_BUILDER.CONFIG.ATTRIBUTE')"
          @update:model-value="set('key', $event)"
        />
        <Input
          :model-value="data.value || ''"
          :label="t('FLOW_BUILDER.CONFIG.VALUE')"
          @update:model-value="set('value', $event)"
        />
        <Select
          model-value=""
          :options="
            variableOptions.filter(item => item.value.startsWith('flow.'))
          "
          :placeholder="t('FLOW_BUILDER.CONFIG.INSERT_VARIABLE')"
          @update:model-value="appendVariable('value', $event)"
        />
      </template>

      <TagMultiSelectComboBox
        v-if="['add_label', 'remove_label'].includes(type)"
        :model-value="data.labels || []"
        :options="labelOptions"
        :placeholder="t('FLOW_BUILDER.CONFIG.LABELS')"
        @update:model-value="set('labels', $event)"
      />

      <ComboBox
        v-if="type === 'assign_team'"
        :model-value="data.team_id || ''"
        :options="teamOptions"
        :placeholder="t('FLOW_BUILDER.CONFIG.TEAM')"
        @update:model-value="set('team_id', $event)"
      />

      <template v-if="type === 'assign_agent'">
        <ComboBox
          :model-value="data.agent_id || ''"
          :options="agentOptions"
          :placeholder="t('FLOW_BUILDER.CONFIG.AGENT')"
          @update:model-value="set('agent_id', $event)"
        />
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('FLOW_BUILDER.CONFIG.ASSIGN_AGENT_HINT') }}
        </p>
      </template>

      <template v-if="type === 'commerce_lookup'">
        <Select
          :model-value="data.mode || 'latest_order'"
          :options="lookupModes"
          @update:model-value="
            setMany({
              mode: $event,
              number: $event === 'order_number' ? data.number : undefined,
            })
          "
        />
        <Input
          v-if="data.mode === 'order_number'"
          :model-value="data.number || ''"
          :label="t('FLOW_BUILDER.CONFIG.ORDER_NUMBER')"
          placeholder="{{flow.reply}}"
          @update:model-value="set('number', $event || undefined)"
        />
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('FLOW_BUILDER.CONFIG.LOOKUP_HINT') }}
        </p>
      </template>

      <template v-if="type === 'webhook'">
        <Input
          :model-value="data.url || ''"
          type="url"
          :label="t('FLOW_BUILDER.CONFIG.URL')"
          placeholder="https://"
          @update:model-value="set('url', $event)"
        />
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('FLOW_BUILDER.CONFIG.WEBHOOK_HINT') }}
        </p>
      </template>

      <Input
        v-if="type === 'delay'"
        :model-value="data.seconds ?? 60"
        type="number"
        min="1"
        max="86400"
        :label="t('FLOW_BUILDER.CONFIG.DELAY_SECONDS')"
        @update:model-value="set('seconds', Number($event))"
      />

      <template v-if="type === 'handoff'">
        <ComboBox
          :model-value="data.team_id || ''"
          :options="teamOptions"
          :placeholder="t('FLOW_BUILDER.CONFIG.TEAM_OPTIONAL')"
          @update:model-value="set('team_id', $event || undefined)"
        />
        <ComboBox
          :model-value="data.agent_id || ''"
          :options="agentOptions"
          :placeholder="t('FLOW_BUILDER.CONFIG.AGENT_OPTIONAL')"
          @update:model-value="set('agent_id', $event || undefined)"
        />
        <Select
          :model-value="data.priority || ''"
          :options="priorities"
          @update:model-value="set('priority', $event || undefined)"
        />
        <TagMultiSelectComboBox
          :model-value="data.labels || []"
          :options="labelOptions"
          :placeholder="t('FLOW_BUILDER.CONFIG.LABELS')"
          @update:model-value="
            set('labels', $event.length ? $event : undefined)
          "
        />
        <TextArea
          :model-value="data.reason || ''"
          :label="t('FLOW_BUILDER.CONFIG.REASON')"
          :max-length="255"
          auto-height
          @update:model-value="set('reason', $event || undefined)"
        />
      </template>

      <ComboBox
        v-if="type === 'goto'"
        :model-value="data.target || ''"
        :options="targetOptions"
        :placeholder="t('FLOW_BUILDER.CONFIG.TARGET')"
        @update:model-value="set('target', $event)"
      />

      <label
        v-if="type === 'end'"
        class="flex items-center gap-2 text-sm text-n-slate-12"
      >
        <Checkbox
          :model-value="data.resolve === true"
          @update:model-value="set('resolve', $event || undefined)"
        />
        {{ t('FLOW_BUILDER.CONFIG.RESOLVE') }}
      </label>
    </div>
  </aside>
</template>
