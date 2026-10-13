<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import AttachmentPicker from './AttachmentPicker.vue';
import { PLATFORM_SUPPORT_REPLY_MAX_LENGTH } from '../constants';

/**
 * The customer's reply box.
 *
 * ALWAYS AVAILABLE ON A RESOLVED TICKET, where replying reopens it -- so the hint says so rather than leaving
 * the customer to guess whether anybody will read it. There is no reply box at all on a `closed` ticket; the
 * page offers a new ticket instead, because the server refuses a reply there with 422.
 */
const props = defineProps({
  // True on a `resolved` ticket: sending reopens it.
  reopens: {
    type: Boolean,
    default: false,
  },
  isSubmitting: {
    type: Boolean,
    default: false,
  },
  // The server's refusal, shown exactly as it came.
  errorMessage: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['send']);

const { t } = useI18n();

const body = ref('');
const attachmentIds = ref([]);
const pickerRef = ref(null);

const canSend = computed(
  () => body.value.trim().length > 0 && !props.isSubmitting
);

const send = () => {
  if (!canSend.value) return;

  emit('send', {
    body: body.value.trim(),
    attachment_ids: attachmentIds.value,
  });
};

/**
 * Empties the box. Called by the page once the server has accepted the reply, so a failed send never loses
 * what the customer typed.
 * @returns {void}
 */
const reset = () => {
  body.value = '';
  attachmentIds.value = [];
  pickerRef.value?.clear();
};

defineExpose({ reset });
</script>

<template>
  <section class="flex flex-col gap-3 pt-4 border-t border-n-weak">
    <h2 class="m-0 text-heading-3 text-n-slate-12">
      {{ t('PLATFORM_SUPPORT.REPLY.TITLE') }}
    </h2>
    <p v-if="reopens" class="m-0 text-body-small text-n-slate-11">
      {{ t('PLATFORM_SUPPORT.REPLY.REOPENS_HINT') }}
    </p>

    <TextArea
      v-model="body"
      :placeholder="t('PLATFORM_SUPPORT.REPLY.PLACEHOLDER')"
      :max-length="PLATFORM_SUPPORT_REPLY_MAX_LENGTH"
      :disabled="isSubmitting"
      :message="errorMessage"
      :message-type="errorMessage ? 'error' : 'info'"
      auto-height
      min-height="5rem"
    />

    <AttachmentPicker
      ref="pickerRef"
      v-model="attachmentIds"
      :disabled="isSubmitting"
    />

    <div class="flex justify-end">
      <Button
        type="button"
        size="sm"
        icon="i-lucide-send"
        :label="t('PLATFORM_SUPPORT.REPLY.SEND')"
        :is-loading="isSubmitting"
        :disabled="!canSend"
        @click="send"
      />
    </div>
  </section>
</template>
