<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatBytes } from 'shared/helpers/FileHelper';
import PlatformSupportAPI from '../platformSupportApi';

// A message's attachments, as named rows with a download action.
//
// NEVER A BARE URL. The payload carries no `url` for an attachment, and this component does not build one: it
// asks the API client for the authorized download path, which streams only after the server has authorized the
// attachment's parent record through the policy scope
// (docs/platform-support/12-refresh-against-product-refinement.md §3). Blob URLs do not expire in this
// installation, so a signed id rendered into a page would be a permanent bearer token.
defineProps({
  attachments: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();

const downloadUrl = attachment => PlatformSupportAPI.attachmentUrl(attachment.id);
</script>

<template>
  <ul v-if="attachments.length" class="flex flex-col gap-1 p-0 m-0 list-none">
    <li v-for="attachment in attachments" :key="attachment.id">
      <a
        :href="downloadUrl(attachment)"
        :download="attachment.filename"
        class="inline-flex items-center max-w-full gap-2 px-2 py-1 border rounded-lg border-n-weak text-n-slate-11 hover:text-n-slate-12 hover:border-n-slate-6"
      >
        <Icon icon="i-lucide-paperclip" class="shrink-0 size-3.5" />
        <span class="truncate text-body-small">{{ attachment.filename }}</span>
        <span class="shrink-0 tabular-nums text-label-small text-n-slate-10">
          {{ formatBytes(attachment.byte_size, 1) }}
        </span>
        <span class="sr-only">{{ t('PLATFORM_SUPPORT.THREAD.DOWNLOAD') }}</span>
      </a>
    </li>
  </ul>
  <!-- Nothing at all when a message carries no attachment: an empty list would still take the parent's gap. -->
  <span v-else class="hidden" />
</template>
