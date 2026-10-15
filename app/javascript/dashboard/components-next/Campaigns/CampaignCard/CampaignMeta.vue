<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  isLiveChatType: {
    type: Boolean,
    default: false,
  },
  status: {
    type: String,
    default: '',
  },
  sender: {
    type: Object,
    default: null,
  },
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
  audience: {
    type: Array,
    default: () => [],
  },
});

const { t, locale } = useI18n();

const senderName = computed(
  () => props.sender?.name || t('CAMPAIGN.LIVE_CHAT.CARD.CAMPAIGN_DETAILS.BOT')
);

// `scheduled_at` is unix SECONDS. The card used to read it through `messageStamp(new Date(scheduledAt), ...)`,
// which lands on the right instant only because building a Date from seconds-as-milliseconds and then
// multiplying by 1000 cancels out -- and then printed it with a hardcoded English pattern, so an Arabic card
// read "Apr 30, 2:15 PM" in the middle of Arabic text.
const scheduledLabel = computed(() =>
  new Intl.DateTimeFormat(locale.value, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(props.scheduledAt * 1000))
);

// EVERY one-off campaign used to say "Sent from <inbox> on <date>", including the ones that had not been sent
// yet and the one that failed to send -- so the clearest line on a blocked campaign's card asserted the exact
// opposite of its status chip. The tense now follows the status.
const SCHEDULE_KEYS = {
  completed: 'SENT',
  processing: 'SENDING',
  blocked: 'MISSED',
};

const scheduleLabel = computed(() => {
  const key = SCHEDULE_KEYS[props.status] || 'SENDS';
  return t(`CAMPAIGN.CARD.SCHEDULE.${key}`, { date: scheduledLabel.value });
});

const audienceCount = computed(() => props.audience?.length ?? 0);
</script>

<template>
  <div
    class="flex flex-wrap items-center w-full gap-x-4 gap-y-1.5 text-sm text-n-slate-11"
  >
    <!-- Live chat: who the visitor sees it from. One-off: when it goes, or went. Both: which inbox. -->
    <span v-if="isLiveChatType" class="flex items-center gap-1.5 min-w-0">
      <Avatar
        :name="senderName"
        :src="sender?.thumbnail"
        :size="16"
        rounded-full
      />
      <span class="truncate text-n-slate-12">{{ senderName }}</span>
    </span>
    <span v-else class="flex items-center gap-1.5 shrink-0">
      <Icon icon="i-lucide-calendar-clock" class="size-3.5 shrink-0" />
      <span class="text-n-slate-12">{{ scheduleLabel }}</span>
    </span>

    <span class="flex items-center gap-1.5 min-w-0">
      <Icon :icon="inboxIcon" class="shrink-0 size-3.5" />
      <span class="truncate text-n-slate-12">{{ inboxName }}</span>
    </span>

    <span
      v-if="audienceCount"
      class="flex items-center gap-1.5 shrink-0"
      data-test-id="campaign-audience"
    >
      <Icon icon="i-lucide-users" class="size-3.5 shrink-0" />
      <span class="text-n-slate-12">
        {{ t('CAMPAIGN.CARD.AUDIENCE', { n: audienceCount }, audienceCount) }}
      </span>
    </span>
  </div>
</template>
