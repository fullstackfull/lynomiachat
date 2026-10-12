<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatBytes } from 'shared/helpers/FileHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import PlatformSupportAPI from '../platformSupportApi';
import {
  PLATFORM_SUPPORT_ACCEPTED_MIME_TYPES,
  PLATFORM_SUPPORT_MAX_ATTACHMENTS,
  PLATFORM_SUPPORT_MAX_ATTACHMENT_BYTES,
} from '../constants';

/**
 * The attachment picker for both compose surfaces.
 *
 * THE LIMITS ARE STATED BEFORE THE PICKER, not after a rejection
 * (docs/platform-support/03-authorization-security.md §7). A customer who learns the rule from an error
 * message has already lost the upload and some of their patience.
 *
 * `modelValue` is the list of signed blob ids to send as `attachment_ids`. Each file is uploaded on selection
 * through the installation's existing scoped upload endpoint, so the create or reply request carries ids and
 * not a multipart body. The server enforces the same limits again and its refusal is shown as it came.
 */
const props = defineProps({
  // The signed blob ids collected so far.
  modelValue: {
    type: Array,
    default: () => [],
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const fileInputRef = ref(null);
// { id, name, size } per accepted file, so a named row can be removed before submit.
const files = ref([]);
const isUploading = ref(false);
const rejection = ref('');

const acceptAttribute = PLATFORM_SUPPORT_ACCEPTED_MIME_TYPES.join(',');

const limitsHint = computed(() =>
  t('PLATFORM_SUPPORT.FORM.ATTACHMENTS_LIMITS', {
    count: PLATFORM_SUPPORT_MAX_ATTACHMENTS,
    size: formatBytes(PLATFORM_SUPPORT_MAX_ATTACHMENT_BYTES, 0),
  })
);

const isFull = computed(
  () => props.modelValue.length >= PLATFORM_SUPPORT_MAX_ATTACHMENTS
);

const reject = file => {
  if (!PLATFORM_SUPPORT_ACCEPTED_MIME_TYPES.includes(file.type)) {
    return t('PLATFORM_SUPPORT.FORM.ATTACHMENT_TYPE_REFUSED', {
      name: file.name,
    });
  }

  if (file.size > PLATFORM_SUPPORT_MAX_ATTACHMENT_BYTES) {
    return t('PLATFORM_SUPPORT.FORM.ATTACHMENT_TOO_LARGE', {
      name: file.name,
      size: formatBytes(PLATFORM_SUPPORT_MAX_ATTACHMENT_BYTES, 0),
    });
  }

  return '';
};

const onPick = async event => {
  const picked = Array.from(event.target.files || []);
  // The input keeps its value otherwise, and picking the same file twice in a row does nothing.
  event.target.value = '';
  if (!picked.length) return;

  rejection.value = '';
  const room = PLATFORM_SUPPORT_MAX_ATTACHMENTS - props.modelValue.length;
  if (picked.length > room) {
    rejection.value = t('PLATFORM_SUPPORT.FORM.ATTACHMENT_COUNT_REFUSED', {
      count: PLATFORM_SUPPORT_MAX_ATTACHMENTS,
    });
    return;
  }

  const refusal = picked.map(reject).find(message => message);
  if (refusal) {
    rejection.value = refusal;
    return;
  }

  isUploading.value = true;
  try {
    // All or nothing: one rejected upload leaves the picker unchanged rather than half-filled, so the
    // customer retries a selection rather than reconstructing which file is missing.
    const uploaded = await Promise.all(
      picked.map(async file => ({
        id: await PlatformSupportAPI.uploadAttachment(file),
        name: file.name,
        size: file.size,
      }))
    );
    files.value = [...files.value, ...uploaded];
    emit('update:modelValue', [
      ...props.modelValue,
      ...uploaded.map(file => file.id),
    ]);
  } catch {
    rejection.value = t('PLATFORM_SUPPORT.FORM.ATTACHMENT_UPLOAD_FAILED');
  } finally {
    isUploading.value = false;
  }
};

const remove = id => {
  files.value = files.value.filter(file => file.id !== id);
  emit(
    'update:modelValue',
    props.modelValue.filter(value => value !== id)
  );
};

/**
 * Drops every picked file. Called by the compose surfaces after a successful submit.
 * @returns {void}
 */
const clear = () => {
  files.value = [];
  rejection.value = '';
  emit('update:modelValue', []);
};

defineExpose({ clear });
</script>

<template>
  <div class="flex flex-col gap-2">
    <p class="m-0 text-body-small text-n-slate-11">{{ limitsHint }}</p>
    <p class="m-0 text-label-small text-n-slate-10">
      {{ t('PLATFORM_SUPPORT.FORM.ATTACHMENTS_TYPES') }}
    </p>

    <div class="flex items-center gap-2">
      <Button
        type="button"
        variant="faded"
        color="slate"
        size="sm"
        icon="i-lucide-paperclip"
        :label="t('PLATFORM_SUPPORT.FORM.ATTACHMENTS_ADD')"
        :is-loading="isUploading"
        :disabled="disabled || isFull || isUploading"
        @click="fileInputRef?.click()"
      />
      <span v-if="isFull" class="text-label-small text-n-slate-10">
        {{
          t('PLATFORM_SUPPORT.FORM.ATTACHMENTS_FULL', {
            count: PLATFORM_SUPPORT_MAX_ATTACHMENTS,
          })
        }}
      </span>
    </div>

    <input
      ref="fileInputRef"
      type="file"
      multiple
      class="hidden"
      :accept="acceptAttribute"
      :aria-label="t('PLATFORM_SUPPORT.FORM.ATTACHMENTS_ADD')"
      @change="onPick"
    />

    <p
      v-if="rejection"
      data-test-id="platform-support-attachment-rejection"
      class="m-0 text-body-small text-n-ruby-9"
    >
      {{ rejection }}
    </p>

    <ul v-if="files.length" class="flex flex-col gap-1 p-0 m-0 list-none">
      <li
        v-for="file in files"
        :key="file.id"
        class="flex items-center gap-2 px-2 py-1 border rounded-lg border-n-weak"
      >
        <Icon
          icon="i-lucide-paperclip"
          class="shrink-0 size-3.5 text-n-slate-10"
        />
        <span class="truncate text-body-small text-n-slate-12">{{
          file.name
        }}</span>
        <span
          class="ms-auto shrink-0 tabular-nums text-label-small text-n-slate-10"
        >
          {{ formatBytes(file.size, 1) }}
        </span>
        <Button
          type="button"
          variant="ghost"
          color="slate"
          size="xs"
          icon="i-lucide-x"
          :disabled="disabled"
          :aria-label="t('PLATFORM_SUPPORT.FORM.ATTACHMENT_REMOVE')"
          @click="remove(file.id)"
        />
      </li>
    </ul>
  </div>
</template>
