<script setup>
import { computed } from 'vue';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useExactTimestamp } from 'shared/composables/useExactTimestamp';
import { useI18n } from 'vue-i18n';
import { articleStatusChip } from 'dashboard/helper/portalHelper';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import MessageFormatter from 'shared/helpers/MessageFormatter';

const props = defineProps({
  id: { type: [String, Number], default: 0 },
  title: { type: String, default: '' },
  description: { type: String, default: '' },
  category: { type: String, default: '' },
  locale: { type: String, default: '' },
  content: { type: String, default: '' },
  portalSlug: { type: String, required: true },
  accountId: { type: [String, Number], default: 0 },
  status: { type: String, default: '' },
  updatedAt: { type: Number, default: 0 },
});

const { t } = useI18n();

const exactTimestamp = useExactTimestamp();

const MAX_LENGTH = 300;

const navigateTo = computed(() => {
  return frontendURL(
    `accounts/${props.accountId}/portals/${props.portalSlug}/${props.locale}/articles/edit/${props.id}`
  );
});

const updatedAtTime = computed(() => {
  if (!props.updatedAt) return '';
  return dynamicTime(props.updatedAt);
});

const truncatedContent = computed(() => {
  if (!props.content) return props.description || '';

  // Use MessageFormatter to properly convert markdown to plain text
  const formatter = new MessageFormatter(props.content);
  const plainText = formatter.plainText.trim();

  return plainText.length > MAX_LENGTH
    ? `${plainText.substring(0, MAX_LENGTH)}...`
    : plainText;
});

const statusChip = computed(() => articleStatusChip(props.status));
</script>

<template>
  <router-link :to="navigateTo">
    <CardLayout
      layout="col"
      class="[&>div]:justify-start [&>div]:gap-2 [&>div]:px-4 [&>div]:pt-4 [&>div]:pb-5 [&>div]:items-start hover:bg-n-slate-2 dark:hover:bg-n-solid-3"
    >
      <div class="min-w-0 flex-1 flex flex-col items-start gap-2 w-full">
        <div class="flex items-center min-w-0 justify-between gap-2 w-full">
          <div class="flex items-center gap-2">
            <h5
              class="text-sm font-medium leading-4 truncate min-w-0 text-n-slate-12"
            >
              {{ title }}
            </h5>
            <div v-if="category" class="w-px h-4 bg-n-strong mx-2" />
            <Label
              v-if="category"
              compact
              variant="subtle"
              tone="neutral"
              :label="category"
              class="capitalize"
            />
            <!-- The same three states the article card shows, from the same map and in the same
                 words — this rendered the raw enum value before. -->
            <Label
              v-if="status"
              compact
              variant="subtle"
              :tone="statusChip.tone"
              :label="t(statusChip.labelKey)"
            />
          </div>
          <span
            v-if="updatedAtTime"
            v-tooltip.top="{
              content: exactTimestamp(updatedAt),
              delay: { show: 500, hide: 0 },
            }"
            class="text-sm font-normal min-w-0 truncate text-n-slate-11"
          >
            {{ updatedAtTime }}
          </span>
        </div>
        <p
          v-if="truncatedContent"
          class="text-sm leading-6 text-n-slate-11 line-clamp-2"
        >
          {{ truncatedContent }}
        </p>
      </div>
    </CardLayout>
  </router-link>
</template>
