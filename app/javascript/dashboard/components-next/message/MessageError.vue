<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import { whatsappErrorArticle } from 'dashboard/helper/documentationLinks';
import { useMessageContext } from './provider.js';
import { hasOneDayPassed } from 'shared/helpers/timeHelper';
import { ORIENTATION, MESSAGE_STATUS } from './constants';

const props = defineProps({
  error: { type: String, required: true },
  // What the server made of the provider's refusal, for the codes it classifies
  // (custom/app/services/whatsapp/delivery_failure.rb). Absent for every other failure, which then reads exactly
  // as it did before: the provider's own words and a retry.
  deliveryFailure: { type: Object, default: null },
});

const emit = defineEmits(['retry']);

const { orientation, status, createdAt, content, attachments } =
  useMessageContext();

const { t } = useI18n();
const { docsLink } = useBranding();

// Before this, the only thing on screen was "Failed to send" and the provider's raw string behind a hover-only
// tooltip, which was clipped by the bubble and unreachable on a touch screen. An agent reading "131049: ..." has no
// way to know whether to try again, whether the number is broken, or whether the customer is at fault. The
// explanation is therefore plain text, not a hover.
const explanation = computed(() => {
  const classification = props.deliveryFailure?.classification;
  if (!classification) return null;

  return {
    title: t(`CHAT_LIST.DELIVERY_FAILURE.${classification}.TITLE`),
    body: t(`CHAT_LIST.DELIVERY_FAILURE.${classification}.BODY`),
  };
});

// Meta's refusal is kept verbatim, whatever Lynomia makes of it: it is the thing an operator quotes to Meta, and
// the thing a classification could be wrong about. It is labelled only once it has been classified, because
// then we know which provider said it.
const providerLabel = computed(() =>
  props.deliveryFailure
    ? t('CHAT_LIST.DELIVERY_FAILURE.PROVIDER_RESPONSE_LABEL')
    : ''
);

// A refusal that follows the recipient rather than the configuration will be given again for the same message to
// the same person, and every attempt is another quality signal against the number. Offering Retry there invites an
// agent to hammer someone Meta has deliberately throttled, so it is withdrawn and the reason is stated instead.
//
// This is NOT every DO_NOT_AUTO_RETRY code: 131042 is billing, an administrator can fix it outside Lynomia, and
// the same message will then send -- so its retry stays.
const retryWouldBeRefused = computed(
  () => props.deliveryFailure?.recipientScoped === true
);

const canRetry = computed(() => {
  if (retryWouldBeRefused.value) return false;

  const hasContent = content.value !== null;
  const hasAttachments = attachments.value && attachments.value.length > 0;
  return !hasOneDayPassed(createdAt.value) && (hasContent || hasAttachments);
});

// The article about this code where one exists, and the general troubleshooting article otherwise. An agent
// reading "131049" wants the page that explains 131049, not the page that explains WhatsApp.
const learnMoreUrl = computed(() => {
  if (!props.deliveryFailure) return '';

  return docsLink(
    whatsappErrorArticle(props.deliveryFailure.code) ??
      'whatsappTroubleshooting'
  );
});

// The block sits against its bubble, but its sentences stay start-aligned. Ragged-left body copy beside an
// outgoing bubble is markedly harder to read than the same three lines set normally, and the explanation is the
// part an agent has to actually read.
const alignmentClass = computed(() =>
  orientation.value === ORIENTATION.RIGHT ? 'items-end' : 'items-start'
);
</script>

<template>
  <!-- The row is kept so the parent's `justify-*` orientation class still places this block against its bubble. -->
  <div class="flex text-xs">
    <div
      class="flex flex-col gap-1 max-w-xs text-start"
      :class="alignmentClass"
    >
      <div class="flex items-center gap-1.5 text-n-ruby-11">
        <Icon icon="i-lucide-alert-triangle" class="size-3.5 shrink-0" />
        <span>{{ t('CHAT_LIST.FAILED_TO_SEND') }}</span>
      </div>

      <template v-if="explanation">
        <p class="text-n-slate-12">{{ explanation.title }}</p>
        <p class="text-n-slate-11">{{ explanation.body }}</p>
      </template>

      <!-- Clamped rather than truncated: an SMTP rejection runs to paragraphs, and the whole of it stays
           available through the title attribute and through the conversation's own API payload. The refusal
           itself is isolated: it is the provider's English, and in an Arabic paragraph its leading error code
           was being reordered to the end of the line. -->
      <p class="text-n-slate-10 break-words line-clamp-3" :title="error">
        <span v-if="providerLabel">{{ providerLabel }}&nbsp;</span>
        <bdi dir="auto">{{ error }}</bdi>
      </p>

      <div class="flex items-center gap-3">
        <a
          v-if="learnMoreUrl"
          :href="learnMoreUrl"
          target="_blank"
          rel="noopener noreferrer"
          class="text-n-blue-11 hover:underline"
        >
          {{ t('CHAT_LIST.DELIVERY_FAILURE.LEARN_MORE') }}
        </a>
        <button
          v-if="canRetry"
          v-tooltip.bottom="t('CHAT_LIST.DELIVERY_FAILURE.RETRY')"
          type="button"
          :aria-label="t('CHAT_LIST.DELIVERY_FAILURE.RETRY')"
          :disabled="status !== MESSAGE_STATUS.FAILED"
          class="grid bg-n-alpha-2 rounded-md size-5 place-content-center cursor-pointer"
          @click="emit('retry')"
        >
          <Icon
            icon="i-lucide-refresh-ccw"
            class="text-n-ruby-11 size-[14px]"
          />
        </button>
        <span v-else-if="retryWouldBeRefused" class="text-n-slate-11">
          {{ t('CHAT_LIST.DELIVERY_FAILURE.NO_RETRY_REASON') }}
        </span>
      </div>
    </div>
  </div>
</template>
