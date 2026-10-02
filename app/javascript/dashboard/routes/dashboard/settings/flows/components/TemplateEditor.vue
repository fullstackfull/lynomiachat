<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import {
  buildTemplateParameters,
  findComponentByType,
  renderTemplatePreview,
} from 'dashboard/helper/templateHelper';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

// The Send template node's settings (docs/flow-builder/04-node-contracts.md §send template). The templates are the
// composer's own list (inboxes/getFilteredWhatsAppTemplates: approved, sendable) of the flow's WhatsApp inboxes, or of
// the account's WhatsApp inboxes while none is connected. Values are kept in the composer's processed_params shape
// (buildTemplateParameters). The server checks the template and every value again on publish.
const props = defineProps({
  modelValue: { type: Object, required: true },
  inboxIds: { type: Array, default: () => [] },
  variables: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');
const templatesOf = useMapGetter('inboxes/getFilteredWhatsAppTemplates');

const templateInboxes = computed(() => {
  const whatsapp = inboxes.value.filter(
    inbox =>
      inbox.channel_type === 'Channel::Whatsapp' &&
      inbox.provider === 'whatsapp_cloud'
  );
  if (!props.inboxIds.length) return whatsapp;
  return whatsapp.filter(inbox => props.inboxIds.includes(inbox.id));
});

const keyOf = template => `${template.name}|${template.language}`;
const templates = computed(() => {
  const found = new Map();
  templateInboxes.value.forEach(inbox =>
    templatesOf.value(inbox.id).forEach(template => {
      if (!found.has(keyOf(template))) found.set(keyOf(template), template);
    })
  );
  return [...found.values()];
});
const templateOptions = computed(() =>
  templates.value.map(template => ({
    value: keyOf(template),
    label: `${template.name} · ${template.language}`,
  }))
);
const template = computed(() =>
  templates.value.find(
    item =>
      item.name === props.modelValue.name &&
      item.language?.toLowerCase() === props.modelValue.language?.toLowerCase()
  )
);
const storedLabel = computed(() =>
  props.modelValue.name
    ? `${props.modelValue.name} · ${props.modelValue.language}`
    : ''
);

const chooseTemplate = key => {
  const picked = templates.value.find(item => keyOf(item) === key);
  if (!picked) return;
  emit('update:modelValue', {
    name: picked.name,
    language: picked.language,
    params: buildTemplateParameters(picked),
  });
};

const params = computed(() => props.modelValue.params || {});
const preview = computed(() => {
  const body = template.value && findComponentByType(template.value, 'BODY');
  return body ? renderTemplatePreview(body.text, params.value.body || {}) : '';
});

const flowVariables = computed(() =>
  props.variables.filter(name => name.startsWith('flow.'))
);

// One field per value the template takes, read from the stored values so a template removed from WhatsApp still shows
// what the node holds.
const fields = computed(() => {
  const { header = {}, body = {}, buttons = [] } = params.value;
  const list = [];
  if ('media_url' in header) {
    list.push({
      section: 'header',
      key: 'media_url',
      label: t('FLOW_BUILDER.CONFIG.TEMPLATE_MEDIA_URL', {
        type: header.media_type || '',
      }),
    });
    if ('media_name' in header) {
      list.push({
        section: 'header',
        key: 'media_name',
        label: t('FLOW_BUILDER.CONFIG.TEMPLATE_MEDIA_NAME'),
        variables: props.variables,
      });
    }
  } else {
    Object.keys(header).forEach(key =>
      list.push({
        section: 'header',
        key,
        label: t('FLOW_BUILDER.CONFIG.TEMPLATE_HEADER', { key }),
        variables: props.variables,
      })
    );
  }
  Object.keys(body).forEach(key =>
    list.push({
      section: 'body',
      key,
      label: t('FLOW_BUILDER.CONFIG.TEMPLATE_BODY', { key }),
      variables: props.variables,
    })
  );
  buttons.forEach((button, index) => {
    if (!button) return;
    const copyCode = button.type === 'copy_code';
    list.push({
      section: 'buttons',
      key: index,
      label: copyCode
        ? t('FLOW_BUILDER.CONFIG.TEMPLATE_COPY_CODE', { key: index + 1 })
        : t('FLOW_BUILDER.CONFIG.TEMPLATE_BUTTON', { key: index + 1 }),
      variables: copyCode ? flowVariables.value : props.variables,
    });
  });
  return list;
});

const valueOf = field =>
  field.section === 'buttons'
    ? params.value.buttons?.[field.key]?.parameter || ''
    : params.value[field.section]?.[field.key] || '';

const setValue = (field, value) => {
  const next = JSON.parse(JSON.stringify(params.value));
  if (field.section === 'buttons') {
    next.buttons[field.key] = { ...next.buttons[field.key], parameter: value };
  } else {
    next[field.section] = { ...next[field.section], [field.key]: value };
  }
  emit('update:modelValue', { ...props.modelValue, params: next });
};

const appendVariable = (field, name) => {
  if (name) setValue(field, `${valueOf(field)}{{${name}}}`);
};
const variableOptions = names =>
  names.map(name => ({ value: name, label: `{{${name}}}` }));
</script>

<template>
  <div class="flex flex-col gap-4" data-test-id="flow-template-editor">
    <p class="m-0 text-xs text-n-slate-11">
      {{ t('FLOW_BUILDER.CONFIG.TEMPLATE_HINT') }}
    </p>
    <p
      v-if="!templateOptions.length"
      class="p-3 m-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
    >
      {{ t('FLOW_BUILDER.CONFIG.TEMPLATE_NONE') }}
    </p>
    <div class="flex flex-col gap-1 text-sm text-n-slate-12">
      {{ t('FLOW_BUILDER.CONFIG.TEMPLATE') }}
      <ComboBox
        :model-value="template ? keyOf(template) : ''"
        :options="templateOptions"
        :display-label="storedLabel"
        :placeholder="t('FLOW_BUILDER.CONFIG.TEMPLATE_PLACEHOLDER')"
        data-test-id="flow-template-select"
        @update:model-value="chooseTemplate"
      />
    </div>
    <p v-if="modelValue.name && !template" class="m-0 text-xs text-n-ruby-11">
      {{ t('FLOW_BUILDER.CONFIG.TEMPLATE_UNAVAILABLE') }}
    </p>
    <p
      v-if="preview"
      dir="auto"
      class="px-3 py-2 m-0 text-sm whitespace-pre-wrap break-words rounded-xl bg-n-alpha-2 text-n-slate-12"
      data-test-id="flow-template-preview"
    >
      {{ preview }}
    </p>
    <div
      v-for="field in fields"
      :key="`${field.section}-${field.key}`"
      class="flex flex-col gap-1"
      :data-test-id="`flow-template-field-${field.section}-${field.key}`"
    >
      <Input
        :model-value="valueOf(field)"
        :label="field.label"
        :data-test-id="`flow-template-${field.section}-${field.key}`"
        @update:model-value="setValue(field, $event)"
      />
      <Select
        v-if="field.variables?.length"
        model-value=""
        :options="variableOptions(field.variables)"
        :placeholder="t('FLOW_BUILDER.CONFIG.INSERT_VARIABLE')"
        @update:model-value="appendVariable(field, $event)"
      />
    </div>
  </div>
</template>
