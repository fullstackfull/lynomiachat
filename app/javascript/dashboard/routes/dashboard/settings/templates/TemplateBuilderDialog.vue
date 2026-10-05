<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';

import { useAlert } from 'dashboard/composables';
import WhatsAppTemplatesAPI from 'dashboard/api/whatsappTemplates';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import TemplatePreview from 'dashboard/components-next/template-preview/TemplatePreview.vue';
import { PLATFORMS } from 'dashboard/services/TemplateConstants';
import {
  TEMPLATE_STARTERS,
  starterContent,
} from 'dashboard/recipes/templateStarters';
import { TEMPLATE_LIMITS } from './templateUtils';

const props = defineProps({
  template: { type: Object, default: null },
  inboxOptions: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved']);

// The parts of a template this manager authors. Carousels, offers, catalogues and authentication templates are
// deliberately absent: Lynomia Chat cannot send them, and WhatsApp writes an authentication template's text itself
// (docs/whatsapp-template-manager/01-meta-api-contract.md section 12).
const HEADER_FORMATS = ['NONE', 'TEXT', 'IMAGE', 'VIDEO', 'DOCUMENT'];
const BUTTON_TYPES = ['QUICK_REPLY', 'URL', 'PHONE_NUMBER', 'COPY_CODE'];
const VARIABLE = /\{\{([^}]+)\}\}/g;

const { t } = useI18n();
const { installationName } = useBranding();
const dialogRef = ref(null);
const isSaving = ref(false);
const problems = ref([]);

const blankForm = () => ({
  inboxId: props.inboxOptions[0]?.value ?? null,
  name: '',
  language: 'en_US',
  category: 'UTILITY',
  parameterFormat: 'POSITIONAL',
  headerFormat: 'NONE',
  headerText: '',
  headerHandle: '',
  body: '',
  footer: '',
  buttons: [],
  examples: {},
});

const form = ref(blankForm());

const isEditing = computed(() => Boolean(props.template));
// WhatsApp allows neither the name nor the language of a template it holds to change, so they are shown and locked.
const isIdentityLocked = computed(() => isEditing.value);

const variablesIn = text =>
  [...String(text).matchAll(VARIABLE)].map(m => m[1].trim());

const bodyVariables = computed(() => variablesIn(form.value.body));
const headerVariables = computed(() =>
  form.value.headerFormat === 'TEXT' ? variablesIn(form.value.headerText) : []
);

const exampleFor = key => form.value.examples[key] ?? '';

const namedExamples = keys =>
  keys.map(key => ({ param_name: key, example: exampleFor(key) }));

// WhatsApp needs a sample for every variable, and the key it reads depends on the parameter format and the component
// (docs/whatsapp-template-manager/01-meta-api-contract.md section 2): body_text is an array of arrays, header_text is
// flat, and the named forms are a list of { param_name, example }.
const textExample = (keys, positionalKey, namedKey) => {
  if (!keys.length) return undefined;
  if (form.value.parameterFormat === 'NAMED') {
    return { [namedKey]: namedExamples(keys) };
  }

  const values = keys.map(key => exampleFor(key));
  return { [positionalKey]: positionalKey === 'body_text' ? [values] : values };
};

const headerComponent = () => {
  const { headerFormat, headerText, headerHandle } = form.value;
  if (headerFormat === 'NONE') return null;
  if (headerFormat !== 'TEXT') {
    return {
      type: 'HEADER',
      format: headerFormat,
      example: headerHandle ? { header_handle: [headerHandle] } : undefined,
    };
  }

  const keys = headerVariables.value;
  return {
    type: 'HEADER',
    format: 'TEXT',
    text: headerText,
    example: textExample(keys, 'header_text', 'header_text_named_params'),
  };
};

const bodyComponent = () => ({
  type: 'BODY',
  text: form.value.body,
  example: textExample(
    bodyVariables.value,
    'body_text',
    'body_text_named_params'
  ),
});

const buttonComponent = () => {
  if (!form.value.buttons.length) return null;

  return {
    type: 'BUTTONS',
    buttons: form.value.buttons.map(button => {
      const payload = { type: button.type, text: button.text };
      if (button.type === 'URL') {
        payload.url = button.url;
        if (variablesIn(button.url).length) payload.example = [button.example];
      }
      if (button.type === 'PHONE_NUMBER')
        payload.phone_number = button.phoneNumber;
      if (button.type === 'COPY_CODE') {
        delete payload.text;
        payload.example = button.example;
      }
      return payload;
    }),
  };
};

const components = computed(() =>
  [
    headerComponent(),
    bodyComponent(),
    form.value.footer ? { type: 'FOOTER', text: form.value.footer } : null,
    buttonComponent(),
  ].filter(Boolean)
);

// The preview is rendered from the draft in hand, with no provider call and no saved record, so it is a drawing of
// what WhatsApp would show -- never a claim that WhatsApp has approved anything.
const previewTemplate = computed(() => ({
  id: props.template?.id ?? 'draft',
  name: form.value.name,
  language: form.value.language,
  category: form.value.category,
  parameter_format: form.value.parameterFormat,
  components: components.value,
}));

const previewVariables = computed(() =>
  Object.fromEntries(
    [...headerVariables.value, ...bodyVariables.value].map(key => [
      key,
      exampleFor(key),
    ])
  )
);

const allVariables = computed(() => [
  ...new Set([...headerVariables.value, ...bodyVariables.value]),
]);

// A starter fills the form and nothing else: no record is created, nothing is sent, and WhatsApp reviews whatever is
// submitted afterwards exactly as it would a template written from scratch.
const applyStarter = starter => {
  const content = starterContent(starter, form.value.language);
  const examples = {};
  (content.examples || []).forEach((value, index) => {
    examples[String(index + 1)] = value;
  });

  form.value = {
    ...form.value,
    name: starter.name,
    category: starter.category,
    parameterFormat: starter.parameterFormat,
    headerFormat: content.header?.format || 'NONE',
    headerText: content.header?.text || '',
    headerHandle: '',
    body: content.body,
    footer: content.footer || '',
    buttons: (content.buttons || []).map(button => ({
      type: button.type,
      text: button.text || '',
      url: button.url || '',
      phoneNumber: button.phone_number || '',
      example: button.example || '',
    })),
    examples,
  };
};

const addButton = () => {
  form.value.buttons.push({
    type: 'QUICK_REPLY',
    text: '',
    url: '',
    phoneNumber: '',
    example: '',
  });
};

const removeButton = index => form.value.buttons.splice(index, 1);

const problemMessage = problem =>
  t(`WHATSAPP_TEMPLATE_MGMT.PROBLEM.${problem.code}`, {
    limit: problem.limit ?? '',
    installationName: installationName.value,
  });

const load = template => {
  problems.value = [];
  if (!template) {
    form.value = blankForm();
    return;
  }

  const find = type =>
    (template.components || []).find(component => component.type === type);
  const header = find('HEADER');
  const body = find('BODY');
  const footer = find('FOOTER');
  const buttons = find('BUTTONS')?.buttons || [];
  const examples = {};
  const collect = (keys, values) =>
    keys.forEach((key, index) => {
      examples[key] = values?.[index] ?? '';
    });

  const bodyKeys = variablesIn(body?.text || '');
  if (template.parameter_format === 'NAMED') {
    (body?.example?.body_text_named_params || []).forEach(entry => {
      examples[entry.param_name] = entry.example;
    });
    (header?.example?.header_text_named_params || []).forEach(entry => {
      examples[entry.param_name] = entry.example;
    });
  } else {
    collect(bodyKeys, body?.example?.body_text?.[0]);
    collect(variablesIn(header?.text || ''), header?.example?.header_text);
  }

  form.value = {
    inboxId: template.inboxes?.[0]?.id ?? props.inboxOptions[0]?.value ?? null,
    name: template.name || '',
    language: template.language || 'en_US',
    category: template.category || 'UTILITY',
    parameterFormat: template.parameter_format || 'POSITIONAL',
    headerFormat: header?.format || 'NONE',
    headerText: header?.format === 'TEXT' ? header.text || '' : '',
    headerHandle: header?.example?.header_handle?.[0] || '',
    body: body?.text || '',
    footer: footer?.text || '',
    buttons: buttons.map(button => ({
      type: button.type,
      text: button.text || '',
      url: button.url || '',
      phoneNumber: button.phone_number || '',
      example: Array.isArray(button.example)
        ? button.example[0] || ''
        : button.example || '',
    })),
    examples,
  };
};

watch(() => props.template, load, { immediate: true });

const payload = () => ({
  name: form.value.name,
  language: form.value.language,
  category: form.value.category,
  parameter_format: form.value.parameterFormat,
  components: components.value,
  ...(isEditing.value ? {} : { inbox_id: form.value.inboxId }),
});

const save = async () => {
  isSaving.value = true;
  problems.value = [];

  try {
    const { data } = isEditing.value
      ? await WhatsAppTemplatesAPI.update(props.template.id, payload())
      : await WhatsAppTemplatesAPI.create(payload());

    problems.value = data.validation_problems || [];
    useAlert(
      t(
        isEditing.value
          ? 'WHATSAPP_TEMPLATE_MGMT.SAVED'
          : 'WHATSAPP_TEMPLATE_MGMT.CREATED'
      )
    );
    emit('saved', data);
    if (!problems.value.length) dialogRef.value?.close();
  } catch (error) {
    const code = error?.response?.data?.error?.code;
    const details = error?.response?.data?.error?.details;
    if (details) problems.value = details;
    useAlert(
      code
        ? t(`WHATSAPP_TEMPLATE_MGMT.ERRORS.${code}`)
        : error?.response?.data?.message ||
            t('WHATSAPP_TEMPLATE_MGMT.ERRORS.GENERIC')
    );
  } finally {
    isSaving.value = false;
  }
};

const open = () => {
  load(props.template);
  dialogRef.value?.open();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    :title="
      isEditing
        ? $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.TITLE_EDIT')
        : $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.TITLE_NEW')
    "
    :confirm-button-label="
      isEditing
        ? $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.SAVE')
        : $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.SAVE_DRAFT')
    "
    :cancel-button-label="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.CANCEL')"
    :is-loading="isSaving"
    @confirm="save"
  >
    <div class="grid gap-6 md:grid-cols-5">
      <div class="flex flex-col gap-4 md:col-span-3">
        <div v-if="!isEditing" class="flex flex-col gap-2">
          <span class="text-heading-5 text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.STARTERS.TITLE') }}
          </span>
          <span class="text-body-main text-n-slate-11">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.STARTERS.HELP') }}
          </span>
          <div class="flex flex-wrap gap-2">
            <!-- type="button": Dialog's content is a <form> whose submit confirms, and Button has no default type,
                 so a chip without this would save the draft instead of filling it. -->
            <Button
              v-for="starter in TEMPLATE_STARTERS"
              :key="starter.id"
              type="button"
              :label="$t(`WHATSAPP_TEMPLATE_MGMT.STARTERS.${starter.id}`)"
              :icon="starter.icon"
              color="slate"
              variant="faded"
              size="sm"
              :data-test-id="`starter-${starter.id}`"
              @click="applyStarter(starter)"
            />
          </div>
        </div>

        <label
          v-if="!isEditing"
          class="flex flex-col gap-1 text-sm text-n-slate-12"
        >
          {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.INBOX.LABEL') }}
          <Select v-model="form.inboxId" :options="inboxOptions" />
          <span class="text-body-main text-n-slate-11">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.INBOX.HELP') }}
          </span>
        </label>
        <div class="grid gap-4 sm:grid-cols-2">
          <Input
            v-model="form.name"
            :label="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.NAME.LABEL')"
            :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.NAME.PLACEHOLDER')"
            :message="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.NAME.HELP')"
            :disabled="isIdentityLocked"
            :maxlength="TEMPLATE_LIMITS.name"
          />
          <Input
            v-model="form.language"
            :label="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.LANGUAGE.LABEL')"
            :placeholder="
              $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.LANGUAGE.PLACEHOLDER')
            "
            :message="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.LANGUAGE.HELP')"
            :disabled="isIdentityLocked"
          />
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <label class="flex flex-col gap-1 text-sm text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.CATEGORY.LABEL') }}
            <Select
              v-model="form.category"
              :options="[
                {
                  value: 'UTILITY',
                  label: $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.CATEGORY.UTILITY'),
                },
                {
                  value: 'MARKETING',
                  label: $t(
                    'WHATSAPP_TEMPLATE_MGMT.BUILDER.CATEGORY.MARKETING'
                  ),
                },
              ]"
            />
            <span class="text-body-main text-n-slate-11">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.CATEGORY.HELP') }}
            </span>
          </label>
          <label class="flex flex-col gap-1 text-sm text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.PARAMETER_FORMAT.LABEL') }}
            <Select
              v-model="form.parameterFormat"
              :options="[
                {
                  value: 'POSITIONAL',
                  label: $t(
                    'WHATSAPP_TEMPLATE_MGMT.BUILDER.PARAMETER_FORMAT.POSITIONAL'
                  ),
                },
                {
                  value: 'NAMED',
                  label: $t(
                    'WHATSAPP_TEMPLATE_MGMT.BUILDER.PARAMETER_FORMAT.NAMED'
                  ),
                },
              ]"
            />
          </label>
        </div>

        <label class="flex flex-col gap-1 text-sm text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.HEADER.LABEL') }}
          <Select
            v-model="form.headerFormat"
            :options="
              HEADER_FORMATS.map(format => ({
                value: format,
                label: $t(`WHATSAPP_TEMPLATE_MGMT.BUILDER.HEADER.${format}`),
              }))
            "
          />
        </label>
        <Input
          v-if="form.headerFormat === 'TEXT'"
          v-model="form.headerText"
          :placeholder="
            $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.HEADER.TEXT_PLACEHOLDER')
          "
          :maxlength="TEMPLATE_LIMITS.headerText"
        />
        <Input
          v-if="!['NONE', 'TEXT'].includes(form.headerFormat)"
          v-model="form.headerHandle"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.HEADER.HANDLE_LABEL')"
          :message="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.HEADER.HANDLE_HELP')"
        />

        <TextArea
          v-model="form.body"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BODY.LABEL')"
          :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BODY.PLACEHOLDER')"
          :message="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BODY.HELP')"
          :max-length="TEMPLATE_LIMITS.body"
          show-character-count
          auto-height
        />
        <Input
          v-model="form.footer"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.FOOTER.LABEL')"
          :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.FOOTER.PLACEHOLDER')"
          :message="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.FOOTER.HELP')"
          :maxlength="TEMPLATE_LIMITS.footer"
        />

        <div v-if="allVariables.length" class="flex flex-col gap-2">
          <span class="text-heading-5 text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.EXAMPLES.TITLE') }}
          </span>
          <span class="text-body-main text-n-slate-11">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.EXAMPLES.HELP') }}
          </span>
          <Input
            v-for="key in allVariables"
            :key="key"
            v-model="form.examples[key]"
            :placeholder="
              $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.EXAMPLES.PLACEHOLDER', {
                name: key,
              })
            "
          />
        </div>

        <div class="flex flex-col gap-3">
          <div class="flex items-center justify-between gap-2">
            <span class="text-heading-5 text-n-slate-12">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.LABEL') }}
            </span>
            <Button
              type="button"
              :label="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.ADD')"
              icon="i-lucide-plus"
              color="slate"
              size="sm"
              :disabled="form.buttons.length >= TEMPLATE_LIMITS.buttons"
              @click="addButton"
            />
          </div>
          <span class="text-body-main text-n-slate-11">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.HELP') }}
          </span>
          <div
            v-for="(button, index) in form.buttons"
            :key="index"
            class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak"
          >
            <div class="flex items-start gap-2">
              <Select
                v-model="button.type"
                class="flex-1"
                :aria-label="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.TYPE')"
                :options="
                  BUTTON_TYPES.map(type => ({
                    value: type,
                    label: $t(`WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.${type}`),
                  }))
                "
              />
              <Button
                type="button"
                icon="i-lucide-trash-2"
                color="ruby"
                size="sm"
                :aria-label="
                  $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.REMOVE', {
                    index: index + 1,
                  })
                "
                @click="removeButton(index)"
              />
            </div>
            <Input
              v-if="button.type !== 'COPY_CODE'"
              v-model="button.text"
              :placeholder="$t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.TEXT')"
              :maxlength="TEMPLATE_LIMITS.buttonText"
            />
            <Input
              v-if="button.type === 'URL'"
              v-model="button.url"
              :placeholder="
                $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.URL_VALUE')
              "
              :maxlength="TEMPLATE_LIMITS.buttonUrl"
            />
            <Input
              v-if="button.type === 'PHONE_NUMBER'"
              v-model="button.phoneNumber"
              :placeholder="
                $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.PHONE_VALUE')
              "
              :maxlength="TEMPLATE_LIMITS.buttonPhone"
            />
            <Input
              v-if="
                button.type === 'COPY_CODE' ||
                (button.type === 'URL' && button.url.includes('{{'))
              "
              v-model="button.example"
              :placeholder="
                $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.BUTTONS.EXAMPLE')
              "
              :maxlength="TEMPLATE_LIMITS.buttonCopyCode"
            />
          </div>
        </div>
      </div>

      <div class="flex flex-col gap-3 md:col-span-2">
        <span class="text-heading-5 text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.PREVIEW') }}
        </span>
        <div class="p-3 rounded-lg bg-n-alpha-1">
          <TemplatePreview
            :template="previewTemplate"
            :variables="previewVariables"
            :platform="PLATFORMS.WHATSAPP"
          />
        </div>
        <div v-if="problems.length" class="flex flex-col gap-2">
          <span class="text-heading-5 text-n-ruby-11">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.PROBLEMS.TITLE') }}
          </span>
          <ul class="flex flex-col gap-1 list-disc list-inside">
            <li
              v-for="(problem, index) in problems"
              :key="`${problem.field}-${problem.code}-${index}`"
              class="text-body-main text-n-ruby-11"
            >
              {{ problemMessage(problem) }}
            </li>
          </ul>
          <span class="text-body-main text-n-slate-11">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.BUILDER.PROBLEMS.NO_GUARANTEE') }}
          </span>
        </div>
      </div>
    </div>
  </Dialog>
</template>
