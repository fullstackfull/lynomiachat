<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import AttachmentPicker from './AttachmentPicker.vue';
import {
  PLATFORM_SUPPORT_CATEGORIES,
  PLATFORM_SUPPORT_DEFAULT_CATEGORY,
  PLATFORM_SUPPORT_DEFAULT_PRIORITY,
  PLATFORM_SUPPORT_DESCRIPTION_MAX_LENGTH,
  PLATFORM_SUPPORT_PRIORITIES,
  PLATFORM_SUPPORT_SUBJECT_MAX_LENGTH,
} from '../constants';

/**
 * The create form: one page, four fields, in the order a customer thinks in
 * (docs/platform-support/04-customer-ux.md §3.2).
 *
 * Validation is minimal on purpose. The three required fields are checked here so the customer is not made to
 * wait for a round trip to be told the subject is empty; every other rule -- the eleven categories, the four
 * priorities, the 255 and 10,000 ceilings, the attachment limits -- is the server's, and its 422 is rendered
 * exactly as it came rather than being second-guessed by a parallel client rule that can drift.
 */
const props = defineProps({
  isSubmitting: {
    type: Boolean,
    default: false,
  },
  // The server's refusal, shown as it came.
  errorMessage: {
    type: String,
    default: '',
  },
  // Pre-selects a category, for the "open a new ticket" link on a closed ticket.
  initialCategory: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();

const category = ref(
  PLATFORM_SUPPORT_CATEGORIES.includes(props.initialCategory)
    ? props.initialCategory
    : PLATFORM_SUPPORT_DEFAULT_CATEGORY
);
const subject = ref('');
const description = ref('');
const priority = ref(PLATFORM_SUPPORT_DEFAULT_PRIORITY);
const attachmentIds = ref([]);
const hasAttempted = ref(false);

const categoryOptions = computed(() =>
  PLATFORM_SUPPORT_CATEGORIES.map(value => ({
    value,
    label: t(`PLATFORM_SUPPORT.ENUMS.CATEGORY.${value.toUpperCase()}`),
  }))
);

const priorityOptions = computed(() =>
  PLATFORM_SUPPORT_PRIORITIES.map(value => ({
    value,
    label: t(`PLATFORM_SUPPORT.ENUMS.PRIORITY.${value.toUpperCase()}`),
  }))
);

const subjectError = computed(() =>
  hasAttempted.value && !subject.value.trim()
    ? t('PLATFORM_SUPPORT.FORM.SUBJECT_REQUIRED')
    : ''
);

const descriptionError = computed(() =>
  hasAttempted.value && !description.value.trim()
    ? t('PLATFORM_SUPPORT.FORM.DESCRIPTION_REQUIRED')
    : ''
);

const isValid = computed(
  () => Boolean(subject.value.trim()) && Boolean(description.value.trim())
);

const submit = () => {
  hasAttempted.value = true;
  if (!isValid.value || props.isSubmitting) return;

  emit('submit', {
    category: category.value,
    subject: subject.value.trim(),
    description: description.value.trim(),
    priority: priority.value,
    attachment_ids: attachmentIds.value,
  });
};
</script>

<template>
  <form
    class="flex flex-col gap-5"
    novalidate
    @submit.prevent="submit"
  >
    <Banner v-if="errorMessage" color="ruby">{{ errorMessage }}</Banner>

    <div class="flex flex-col gap-1.5">
      <label for="platform-support-category" class="text-label-small text-n-slate-12">
        {{ t('PLATFORM_SUPPORT.FORM.CATEGORY') }}
      </label>
      <Select
        id="platform-support-category"
        v-model="category"
        class="!w-full"
        :options="categoryOptions"
        :aria-label="t('PLATFORM_SUPPORT.FORM.CATEGORY')"
      />
      <p class="m-0 text-label-small text-n-slate-10">
        {{ t('PLATFORM_SUPPORT.FORM.CATEGORY_HINT') }}
      </p>
    </div>

    <Input
      v-model="subject"
      :label="t('PLATFORM_SUPPORT.FORM.SUBJECT')"
      :placeholder="t('PLATFORM_SUPPORT.FORM.SUBJECT_PLACEHOLDER')"
      :maxlength="PLATFORM_SUPPORT_SUBJECT_MAX_LENGTH"
      :message="subjectError"
      :message-type="subjectError ? 'error' : 'info'"
      :disabled="isSubmitting"
    />

    <TextArea
      v-model="description"
      :label="t('PLATFORM_SUPPORT.FORM.DESCRIPTION_LABEL')"
      :placeholder="t('PLATFORM_SUPPORT.FORM.DESCRIPTION_PLACEHOLDER')"
      :max-length="PLATFORM_SUPPORT_DESCRIPTION_MAX_LENGTH"
      :message="descriptionError || t('PLATFORM_SUPPORT.FORM.DESCRIPTION_HINT')"
      :message-type="descriptionError ? 'error' : 'info'"
      :disabled="isSubmitting"
      auto-height
      min-height="8rem"
    />

    <div class="flex flex-col gap-1.5">
      <label for="platform-support-priority" class="text-label-small text-n-slate-12">
        {{ t('PLATFORM_SUPPORT.FORM.PRIORITY') }}
      </label>
      <Select
        id="platform-support-priority"
        v-model="priority"
        class="!w-full"
        :options="priorityOptions"
        :aria-label="t('PLATFORM_SUPPORT.FORM.PRIORITY')"
      />
      <p class="m-0 text-label-small text-n-slate-10">
        {{ t('PLATFORM_SUPPORT.FORM.PRIORITY_HINT') }}
      </p>
    </div>

    <div class="flex flex-col gap-1.5">
      <span class="text-label-small text-n-slate-12">
        {{ t('PLATFORM_SUPPORT.FORM.ATTACHMENTS') }}
      </span>
      <AttachmentPicker v-model="attachmentIds" :disabled="isSubmitting" />
    </div>

    <div class="flex items-center justify-end gap-2">
      <Button
        type="button"
        variant="ghost"
        color="slate"
        size="sm"
        :label="t('PLATFORM_SUPPORT.FORM.CANCEL')"
        :disabled="isSubmitting"
        @click="emit('cancel')"
      />
      <Button
        type="submit"
        size="sm"
        :label="t('PLATFORM_SUPPORT.FORM.SUBMIT')"
        :is-loading="isSubmitting"
        :disabled="isSubmitting"
      />
    </div>
  </form>
</template>
