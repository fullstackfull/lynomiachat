<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import {
  TemplateNormalizer,
  TemplatePreview,
} from 'dashboard/components-next/template-preview';
import { PLATFORMS } from 'dashboard/services/TemplateConstants';
import Label from 'dashboard/components-next/label/Label.vue';
import {
  formatTemplateDate,
  formatTemplateLabel,
  formatTemplateLanguage,
  templateStatusLabelKey,
  templateStatusTone,
  templateTypeKey,
} from './templateUtils';

const props = defineProps({
  template: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['action']);

const { t } = useI18n();
const META_TEMPLATE_MANAGER_URL =
  'https://business.facebook.com/latest/whatsapp_manager/message_templates';
const TWILIO_TEMPLATE_MANAGER_URL =
  'https://console.twilio.com/us1/develop/sms/content-editor';

const panelRef = ref(null);

const platform = computed(() => props.template?.platform || PLATFORMS.WHATSAPP);
const normalizedTemplate = computed(() =>
  props.template
    ? TemplateNormalizer.normalize(props.template, platform.value)
    : null
);
const variables = computed(() => normalizedTemplate.value?.variables || {});
const managementUrl = computed(() => {
  if (platform.value === PLATFORMS.TWILIO) {
    return TWILIO_TEMPLATE_MANAGER_URL;
  }

  return props.template?.inboxes?.some(
    inbox => inbox.provider === 'whatsapp_cloud'
  )
    ? META_TEMPLATE_MANAGER_URL
    : null;
});
const managementLabel = computed(() =>
  platform.value === PLATFORMS.TWILIO
    ? t('WHATSAPP_TEMPLATE_MGMT.MANAGE_IN_TWILIO')
    : t('WHATSAPP_TEMPLATE_MGMT.MANAGE_IN_META')
);
const statusLabel = computed(() => {
  const key = templateStatusLabelKey(props.template?.status);

  return key ? t(key) : formatTemplateLabel(props.template?.status);
});

// Everything below is what the manager knows and the synced list never did: whether WhatsApp has seen the template
// at all, what it said when it refused, and what may be done about it.
const isManaged = computed(() => Boolean(props.template?.isManaged));
const isDraft = computed(() => props.template?.state === 'draft');
const isCsat = computed(() =>
  Boolean(props.template?.name?.startsWith('customer_satisfaction_survey'))
);
const rejection = computed(() => {
  const info = props.template?.rejection_info;
  const reason = props.template?.rejected_reason;
  if (!info && (!reason || reason === 'NONE')) return null;

  return (
    [info?.reason, info?.recommendation].filter(Boolean).join(' ') ||
    formatTemplateLabel(reason)
  );
});
const quality = computed(() => props.template?.quality_score?.score || null);
const actions = computed(() =>
  ['submit', 'edit', 'duplicate', 'delete'].filter(action =>
    (props.template?.allowed_actions || []).includes(action)
  )
);
const open = () => panelRef.value?.open();
const close = () => panelRef.value?.close();

defineExpose({ open, close });
</script>

<template>
  <SidePanel
    ref="panelRef"
    width="md"
    :title="template?.name"
    :description="$t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.DESCRIPTION')"
  >
    <div v-if="template" class="flex flex-col gap-6">
      <div
        class="flex items-center justify-center px-6 py-10 border rounded-xl min-h-80 border-n-weak bg-n-alpha-1"
      >
        <TemplatePreview
          :template="template"
          :variables="variables"
          :platform="platform"
        />
      </div>

      <div>
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.DETAILS') }}
        </h3>
        <dl class="grid grid-cols-[8rem_1fr] gap-x-4 gap-y-3 mt-4 text-sm">
          <dt class="text-n-slate-10">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.STATUS') }}
          </dt>
          <dd>
            <Label
              compact
              :label="statusLabel"
              :tone="templateStatusTone(template.status).tone"
              :variant="templateStatusTone(template.status).variant"
            />
          </dd>
          <dt class="text-n-slate-10">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.TYPE') }}
          </dt>
          <dd class="text-n-slate-12">
            {{
              $t(`WHATSAPP_TEMPLATE_MGMT.TYPES.${templateTypeKey(template)}`)
            }}
          </dd>
          <dt class="text-n-slate-10">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.CATEGORY') }}
          </dt>
          <dd class="text-n-slate-12">
            {{ formatTemplateLabel(template.category) }}
          </dd>
          <dt class="text-n-slate-10">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.LANGUAGE') }}
          </dt>
          <dd class="text-n-slate-12">
            {{ formatTemplateLanguage(template.language) }}
          </dd>
          <dt class="text-n-slate-10">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.INBOXES') }}
          </dt>
          <dd class="text-n-slate-12">{{ template.inboxNames }}</dd>
          <template v-if="quality">
            <dt class="text-n-slate-10">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.DETAIL.QUALITY') }}
            </dt>
            <dd class="text-n-slate-12">{{ formatTemplateLabel(quality) }}</dd>
          </template>
          <template v-if="template.submitted_at">
            <dt class="text-n-slate-10">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.DETAIL.SUBMITTED_AT') }}
            </dt>
            <dd class="text-n-slate-12">
              {{ formatTemplateDate(template.submitted_at * 1000) }}
            </dd>
          </template>
          <template v-if="template.last_seen_at">
            <dt class="text-n-slate-10">
              {{ $t('WHATSAPP_TEMPLATE_MGMT.DETAIL.LAST_SEEN') }}
            </dt>
            <dd class="text-n-slate-12">
              {{ formatTemplateDate(template.last_seen_at * 1000) }}
            </dd>
          </template>
        </dl>
      </div>

      <div v-if="isManaged" class="flex flex-col gap-3">
        <p v-if="isDraft" class="text-body-main text-n-slate-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.DETAIL.DRAFT_NOTICE') }}
        </p>
        <p v-if="isCsat" class="text-body-main text-n-slate-11">
          {{ $t('WHATSAPP_TEMPLATE_MGMT.DETAIL.CSAT_NOTICE') }}
        </p>
        <p
          v-if="template.missing_at_meta"
          class="text-body-main text-n-ruby-11"
        >
          {{
            $t('WHATSAPP_TEMPLATE_MGMT.DETAIL.MISSING_NOTICE', {
              date: formatTemplateDate(template.last_seen_at * 1000),
            })
          }}
        </p>
        <div v-if="template.submission_error" class="flex flex-col gap-1">
          <span class="text-heading-5 text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.DETAIL.SUBMISSION_ERROR') }}
          </span>
          <span class="text-body-main text-n-ruby-11">
            {{ template.submission_error }}
          </span>
        </div>
        <div v-if="rejection" class="flex flex-col gap-1">
          <span class="text-heading-5 text-n-slate-12">
            {{ $t('WHATSAPP_TEMPLATE_MGMT.DETAIL.REJECTION') }}
          </span>
          <span class="text-body-main text-n-ruby-11">{{ rejection }}</span>
        </div>
      </div>
    </div>

    <template v-if="actions.length || managementUrl" #footer>
      <div class="flex flex-col gap-2">
        <Button
          v-for="action in actions"
          :key="action"
          class="w-full"
          :label="$t(`WHATSAPP_TEMPLATE_MGMT.ACTIONS.${action.toUpperCase()}`)"
          :color="action === 'delete' ? 'ruby' : 'blue'"
          :variant="action === 'submit' ? 'solid' : 'faded'"
          @click="emit('action', action)"
        />
        <a
          v-if="managementUrl"
          :href="managementUrl"
          target="_blank"
          rel="noopener noreferrer"
        >
          <Button
            class="w-full"
            :label="managementLabel"
            icon="i-lucide-external-link"
            color="slate"
            variant="faded"
            trailing-icon
          />
        </a>
      </div>
    </template>
  </SidePanel>
</template>
