<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import AttachmentList from './AttachmentList.vue';
import { PLATFORM_SUPPORT_AUTHOR_LYNOMIA } from '../constants';

// One public message in the thread.
//
// The operator side is attributed to "Lynomia Support" and nothing else. The API never serializes the
// individual's name -- `author_name` is the literal string for every operator message -- so there is no name
// here to leak and none to invent (docs/platform-support/12-refresh-against-product-refinement.md §2).
//
// `body` is PLAIN TEXT by contract: no HTML, no markdown, no rich editor. It is rendered as text with
// `whitespace-pre-wrap`, never through a markdown renderer or `v-html`.
const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const isFromLynomia = computed(
  () => props.message.author_role === PLATFORM_SUPPORT_AUTHOR_LYNOMIA
);

const authorLabel = computed(() =>
  isFromLynomia.value
    ? t('PLATFORM_SUPPORT.THREAD.LYNOMIA_SUPPORT')
    : props.message.author_name
);
</script>

<template>
  <li class="flex flex-col gap-2 list-none">
    <div class="flex flex-wrap items-baseline gap-2">
      <span class="text-label-small text-n-slate-12">{{ authorLabel }}</span>
      <time class="tabular-nums text-label-small text-n-slate-10">
        {{ messageTimestamp(message.created_at, 'MMM d, yyyy h:mm a') }}
      </time>
    </div>
    <div
      class="flex flex-col gap-2 p-3 border rounded-xl border-n-weak"
      :class="isFromLynomia ? 'bg-n-alpha-1 border-n-brand/20' : 'bg-n-solid-1'"
    >
      <p class="m-0 whitespace-pre-wrap break-words text-body-main text-n-slate-12">
        {{ message.body }}
      </p>
      <AttachmentList :attachments="message.attachments || []" />
    </div>
  </li>
</template>
