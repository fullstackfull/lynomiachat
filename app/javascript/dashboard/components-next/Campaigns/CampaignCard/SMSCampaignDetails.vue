<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  inboxName: {
    type: String,
    default: '',
  },
  inboxIcon: {
    type: String,
    default: '',
  },
  scheduledAt: {
    type: Number,
    default: 0,
  },
});

const { t, locale } = useI18n();

// `scheduled_at` is unix SECONDS. This read `messageStamp(new Date(scheduledAt), 'LLL d, h:mm a')`,
// which lands on the right instant only because building a Date from seconds-as-milliseconds and
// then multiplying by 1000 cancels out -- and then printed it with a hardcoded English pattern, so
// an Arabic card read "Apr 30, 2:15 PM" in the middle of Arabic text.
const scheduledLabel = computed(() =>
  new Intl.DateTimeFormat(locale.value, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(props.scheduledAt * 1000))
);
</script>

<template>
  <span class="flex-shrink-0 text-sm text-n-slate-11 whitespace-nowrap">
    {{ t('CAMPAIGN.SMS.CARD.CAMPAIGN_DETAILS.SENT_FROM') }}
  </span>
  <div class="flex items-center gap-1.5 flex-shrink-0">
    <Icon :icon="inboxIcon" class="flex-shrink-0 text-n-slate-12 size-3" />
    <span class="text-sm font-medium text-n-slate-12">
      {{ inboxName }}
    </span>
  </div>

  <span class="flex-shrink-0 text-sm text-n-slate-11 whitespace-nowrap">
    {{ t('CAMPAIGN.SMS.CARD.CAMPAIGN_DETAILS.ON') }}
  </span>
  <span class="flex-1 text-sm font-medium truncate text-n-slate-12">
    {{ scheduledLabel }}
  </span>
</template>
