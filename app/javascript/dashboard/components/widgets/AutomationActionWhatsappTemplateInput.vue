<script setup>
/**
 * Configures the `send_whatsapp_template` automation action
 * (docs/pre-p7-closeout/03-template-automation-action.md).
 *
 * A Commerce trigger has to be able to reach a shopper whose 24-hour service window has closed, and the only thing
 * WhatsApp permits there is an approved template. This control picks one and collects its variables; it does not
 * decide any template rule of its own. Everything it knows about templates comes from code that already decided
 * those rules:
 *
 *   which inboxes      inboxes/getWhatsAppInboxes
 *   which templates    inboxes/getFilteredWhatsAppTemplates — already filtered by @chatwoot/utils isSendableTemplate
 *   which variables    buildTemplateParameters (buildWhatsAppProcessedParams)
 *   when it is ready   isWhatsAppComplete — the same completeness rule the composer and the mobile app use
 *
 * Language is part of a template's identity rather than a separate field, because the send gate matches on name AND
 * language: the same name can exist in several languages and only some of them approved, so offering a free
 * language select would let a user build a rule the sender must then refuse.
 *
 * The value it emits is the action's own config object. `generatePayload` wraps a non-`id` object as
 * `[object]`, which is exactly the `action_params` shape the backend action reads.
 */
import { ref, computed, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { isWhatsAppComplete } from '@chatwoot/utils';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import {
  buildTemplateParameters,
  COMPONENT_TYPES,
  MEDIA_FORMATS,
  findComponentByType,
} from 'dashboard/helper/templateHelper';

const props = defineProps({
  modelValue: { type: Object, default: () => ({}) },
  dropdownMaxHeight: { type: String, default: 'max-h-80' },
});
const emit = defineEmits(['update:modelValue']);

const MEDIA_KEYS = ['media_url', 'media_name', 'media_type'];
const templateKey = template => `${template.name}::${template.language}`;

const inboxId = ref(props.modelValue?.inbox_id ?? null);
const selectedKey = ref(
  props.modelValue?.name
    ? `${props.modelValue.name}::${props.modelValue.language}`
    : null
);
const processedParams = ref(props.modelValue?.params ?? {});

const whatsappInboxes = useMapGetter('inboxes/getWhatsAppInboxes');
const sendableTemplatesFor = useMapGetter(
  'inboxes/getFilteredWhatsAppTemplates'
);

const inboxOptions = computed(() =>
  whatsappInboxes.value.map(inbox => ({ id: inbox.id, name: inbox.name }))
);

// Only the chosen inbox's own synced templates, which is what makes another account's or another WABA's template
// unreachable here rather than merely discouraged.
const templates = computed(() =>
  inboxId.value ? sendableTemplatesFor.value(inboxId.value) || [] : []
);

const templateOptions = computed(() =>
  templates.value.map(template => ({
    id: templateKey(template),
    name: `${template.name} (${template.language})`,
  }))
);

const selectedTemplate = computed(() =>
  templates.value.find(template => templateKey(template) === selectedKey.value)
);

const headerComponent = computed(() =>
  selectedTemplate.value
    ? findComponentByType(selectedTemplate.value, COMPONENT_TYPES.HEADER)
    : null
);
const hasMediaHeader = computed(() =>
  MEDIA_FORMATS.includes(headerComponent.value?.format)
);
const isDocumentHeader = computed(
  () => headerComponent.value?.format?.toLowerCase() === 'document'
);

const bodyKeys = computed(() => Object.keys(processedParams.value?.body || {}));
const headerTextKeys = computed(() =>
  Object.keys(processedParams.value?.header || {}).filter(
    key => !MEDIA_KEYS.includes(key)
  )
);
const buttonCount = computed(
  () => (processedParams.value?.buttons || []).length
);

const isComplete = computed(() =>
  selectedTemplate.value
    ? isWhatsAppComplete(selectedTemplate.value, processedParams.value)
    : false
);

const asSelectModel = (options, id) =>
  options.find(option => option.id === id) || null;

const publish = () => {
  const template = selectedTemplate.value;
  emit('update:modelValue', {
    inbox_id: inboxId.value,
    name: template?.name ?? null,
    language: template?.language ?? null,
    params: processedParams.value,
  });
};

// Changing the inbox invalidates the template, and changing the template invalidates its variables: a stale
// mapping from a previous template would be silently submitted against the new one.
watch(inboxId, () => {
  selectedKey.value = null;
  processedParams.value = {};
  publish();
});

watch(selectedKey, () => {
  processedParams.value = selectedTemplate.value
    ? buildTemplateParameters(selectedTemplate.value, hasMediaHeader.value)
    : {};
  publish();
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <SingleSelect
      :model-value="asSelectModel(inboxOptions, inboxId)"
      :options="inboxOptions"
      :dropdown-max-height="dropdownMaxHeight"
      :placeholder="$t('AUTOMATION.ACTION.WHATSAPP_TEMPLATE.INBOX')"
      @update:model-value="value => (inboxId = value?.id ?? null)"
    />

    <SingleSelect
      v-if="inboxId"
      :model-value="asSelectModel(templateOptions, selectedKey)"
      :options="templateOptions"
      :dropdown-max-height="dropdownMaxHeight"
      :placeholder="$t('AUTOMATION.ACTION.WHATSAPP_TEMPLATE.TEMPLATE')"
      @update:model-value="value => (selectedKey = value?.id ?? null)"
    />

    <p
      v-if="inboxId && templateOptions.length === 0"
      class="text-sm text-n-slate-11"
    >
      {{ $t('AUTOMATION.ACTION.WHATSAPP_TEMPLATE.NONE_APPROVED') }}
    </p>

    <template v-if="selectedTemplate">
      <NextInput
        v-for="key in headerTextKeys"
        :key="`header-${key}`"
        v-model="processedParams.header[key]"
        size="sm"
        :label="
          $t('AUTOMATION.ACTION.WHATSAPP_TEMPLATE.HEADER_VARIABLE', { key })
        "
        @update:model-value="publish"
      />
      <NextInput
        v-if="hasMediaHeader"
        v-model="processedParams.header.media_url"
        size="sm"
        :label="$t('AUTOMATION.ACTION.WHATSAPP_TEMPLATE.MEDIA_URL')"
        @update:model-value="publish"
      />
      <NextInput
        v-if="hasMediaHeader && isDocumentHeader"
        v-model="processedParams.header.media_name"
        size="sm"
        :label="$t('AUTOMATION.ACTION.WHATSAPP_TEMPLATE.MEDIA_NAME')"
        @update:model-value="publish"
      />
      <NextInput
        v-for="key in bodyKeys"
        :key="`body-${key}`"
        v-model="processedParams.body[key]"
        size="sm"
        :label="
          $t('AUTOMATION.ACTION.WHATSAPP_TEMPLATE.BODY_VARIABLE', { key })
        "
        @update:model-value="publish"
      />
      <NextInput
        v-for="index in buttonCount"
        :key="`button-${index}`"
        v-model="processedParams.buttons[index - 1].parameter"
        size="sm"
        :label="
          $t('AUTOMATION.ACTION.WHATSAPP_TEMPLATE.BUTTON_VARIABLE', { index })
        "
        @update:model-value="publish"
      />

      <p v-if="!isComplete" class="text-sm text-n-ruby-11">
        {{ $t('AUTOMATION.ACTION.WHATSAPP_TEMPLATE.INCOMPLETE') }}
      </p>
    </template>
  </div>
</template>
