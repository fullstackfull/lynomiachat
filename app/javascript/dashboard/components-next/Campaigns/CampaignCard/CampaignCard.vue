<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { getInboxIconByType } from 'dashboard/helper/inbox';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import LiveChatCampaignDetails from './LiveChatCampaignDetails.vue';
import SMSCampaignDetails from './SMSCampaignDetails.vue';

const props = defineProps({
  title: {
    type: String,
    default: '',
  },
  message: {
    type: String,
    default: '',
  },
  isLiveChatType: {
    type: Boolean,
    default: false,
  },
  isEnabled: {
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
  inbox: {
    type: Object,
    default: null,
  },
  scheduledAt: {
    type: Number,
    default: 0,
  },
  showAnalytics: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['edit', 'delete', 'analytics']);

const { t } = useI18n();

const STATUS_COMPLETED = 'completed';
const STATUS_PROCESSING = 'processing';

const { formatMessage } = useMessageFormatter();

// A live-chat campaign is on or off; a one-off campaign moves scheduled -> processing -> completed. Those
// are five states, not two, and 04-status-vocabulary already has a tone for each.
const ONE_OFF_TONES = {
  [STATUS_COMPLETED]: 'success',
  [STATUS_PROCESSING]: 'info',
};

const statusTone = computed(() => {
  if (props.isLiveChatType) return props.isEnabled ? 'success' : 'neutral';
  return ONE_OFF_TONES[props.status] || 'warning';
});

const campaignStatus = computed(() => {
  if (props.isLiveChatType) {
    return props.isEnabled
      ? t('CAMPAIGN.LIVE_CHAT.CARD.STATUS.ENABLED')
      : t('CAMPAIGN.LIVE_CHAT.CARD.STATUS.DISABLED');
  }

  if (props.status === STATUS_COMPLETED) {
    return t('CAMPAIGN.SMS.CARD.STATUS.COMPLETED');
  }

  if (props.status === STATUS_PROCESSING) {
    return t('CAMPAIGN.SMS.CARD.STATUS.PROCESSING');
  }

  return t('CAMPAIGN.SMS.CARD.STATUS.SCHEDULED');
});

const inboxName = computed(() => props.inbox?.name || '');

const inboxIcon = computed(() => {
  const {
    medium,
    channel_type: type,
    voice_enabled: voiceEnabled,
  } = props.inbox;
  return getInboxIconByType(type, medium, 'fill', voiceEnabled);
});
</script>

<template>
  <CardLayout layout="row">
    <div class="flex flex-col items-start justify-between flex-1 min-w-0 gap-2">
      <div class="flex items-center gap-3 w-full min-w-0">
        <span
          :title="title"
          class="min-w-0 text-base font-medium capitalize text-n-slate-12 line-clamp-1"
        >
          {{ title }}
        </span>
        <Label
          compact
          variant="subtle"
          :tone="statusTone"
          :label="campaignStatus"
        />
      </div>
      <div
        v-dompurify-html="formatMessage(message, false, false, false)"
        dir="auto"
        class="text-sm text-n-slate-11 line-clamp-1 [&>p]:mb-0 h-6"
      />
      <div
        class="flex flex-wrap items-center w-full gap-x-2 gap-y-1 h-auto md:h-6 md:flex-nowrap md:overflow-hidden"
      >
        <LiveChatCampaignDetails
          v-if="isLiveChatType"
          :sender="sender"
          :inbox-name="inboxName"
          :inbox-icon="inboxIcon"
        />
        <SMSCampaignDetails
          v-else
          :inbox-name="inboxName"
          :inbox-icon="inboxIcon"
          :scheduled-at="scheduledAt"
        />
      </div>
    </div>
    <div class="flex items-center justify-end shrink-0 gap-2">
      <Button
        v-if="showAnalytics"
        v-tooltip.top="t('CAMPAIGN.WHATSAPP.CARD.ANALYTICS')"
        :aria-label="t('CAMPAIGN.WHATSAPP.CARD.ANALYTICS')"
        variant="faded"
        size="sm"
        color="slate"
        icon="i-lucide-chart-no-axes-column"
        @click="emit('analytics')"
      />
      <Button
        v-if="isLiveChatType"
        variant="faded"
        size="sm"
        color="slate"
        icon="i-lucide-sliders-vertical"
        :aria-label="$t('CAMPAIGN.CARD.EDIT')"
        @click="emit('edit')"
      />
      <Button
        variant="faded"
        color="ruby"
        size="sm"
        icon="i-lucide-trash"
        :aria-label="$t('CAMPAIGN.CARD.DELETE')"
        @click="emit('delete')"
      />
    </div>
  </CardLayout>
</template>
