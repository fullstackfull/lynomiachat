<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { getInboxIconByType } from 'dashboard/helper/inbox';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import CampaignMeta from './CampaignMeta.vue';

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
  audience: {
    type: Array,
    default: () => [],
  },
  showAnalytics: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['edit', 'delete', 'analytics', 'cancel']);

const { t } = useI18n();

const STATUS_COMPLETED = 'completed';
const STATUS_PROCESSING = 'processing';
// DECISION 6: a scheduled WhatsApp campaign that reached its send time while the capability was unavailable.
// Without its own branch it fell through to "Scheduled" below, which is the silence the decision removes.
const STATUS_BLOCKED = 'blocked';
// Cancelled had no branch either, so it fell through to "Scheduled" in amber -- an operator
// who had just stopped a half-sent campaign saw it described as waiting for its send time,
// and `mark_processing!` refuses a cancelled campaign, so it waited there forever.
const STATUS_CANCELLED = 'cancelled';

const { formatMessage } = useMessageFormatter();

// A live-chat campaign is on or off; a one-off campaign moves scheduled -> processing -> completed. Those
// are five states, not two, and 04-status-vocabulary already has a tone for each.
const ONE_OFF_TONES = {
  [STATUS_COMPLETED]: 'success',
  [STATUS_PROCESSING]: 'info',
  // `danger`, not the `warning` that scheduled falls through to: this campaign did not send and will not until
  // somebody acts, so it must not look like one that is merely waiting for its time.
  [STATUS_BLOCKED]: 'danger',
  // `neutral`, not `danger`: nothing is wrong and nobody needs to act -- a person stopped
  // this on purpose and it is finished, in the way a completed campaign is finished.
  [STATUS_CANCELLED]: 'neutral',
};

const statusTone = computed(() => {
  if (props.status === STATUS_CANCELLED) return ONE_OFF_TONES[STATUS_CANCELLED];
  if (props.isLiveChatType) return props.isEnabled ? 'success' : 'neutral';
  return ONE_OFF_TONES[props.status] || 'warning';
});

// WHEN THERE IS SOMETHING LEFT TO STOP. `Campaign#cancel!` refuses a completed or an
// already-cancelled campaign and accepts everything else, so the button is offered for
// exactly the states the server will act on. A live-chat campaign has its own reversible
// switch and is left to it.
const canCancel = computed(
  () =>
    !props.isLiveChatType &&
    ![STATUS_COMPLETED, STATUS_CANCELLED].includes(props.status)
);

const campaignStatus = computed(() => {
  // CANCELLED IS READ FIRST, AND FOR EVERY TYPE. An ongoing campaign reports enabled or
  // disabled, which is a reversible switch -- and cancelling is not reversible, and now
  // genuinely stops an ongoing campaign (Campaigns::CampaignConversationBuilder refuses
  // it). Leaving the enabled/disabled reading in front of it told an operator the campaign
  // was still on.
  if (props.status === STATUS_CANCELLED) {
    return t('CAMPAIGN.SMS.CARD.STATUS.CANCELLED');
  }

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

  if (props.status === STATUS_BLOCKED) {
    return t('CAMPAIGN.SMS.CARD.STATUS.BLOCKED');
  }

  if (props.status === STATUS_CANCELLED) {
    return t('CAMPAIGN.SMS.CARD.STATUS.CANCELLED');
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

// A campaign that is off, finished or blocked is not the one you are looking for in a list of twelve, so its
// channel tile drops to the neutral ramp. The title keeps its contrast either way -- dimming the text of a
// disabled row is the usual way this is done and it costs the people who most need to read it.
const isMuted = computed(() => {
  if (props.isLiveChatType) return !props.isEnabled;
  return props.status === STATUS_COMPLETED || props.status === STATUS_BLOCKED;
});
</script>

<template>
  <CardLayout layout="row">
    <div
      class="grid self-start mt-0.5 shrink-0 place-items-center size-10 rounded-xl"
      :class="isMuted ? 'bg-n-alpha-2' : 'bg-n-brand/10'"
      :title="t('CAMPAIGN.CARD.CHANNEL')"
    >
      <Icon
        :icon="inboxIcon"
        class="size-[18px]"
        :class="isMuted ? 'text-n-slate-11' : 'text-n-brand'"
      />
    </div>

    <div class="flex flex-col items-start justify-between flex-1 min-w-0 gap-2">
      <!-- Wrapping, because the status chip is `shrink-0` and "Not sent -- channel unavailable" is 170px
      wide: at phone width it took the row and left the title rendering as a single letter. The chip drops
      to its own line instead. -->
      <div class="flex flex-wrap items-center w-full min-w-0 gap-x-3 gap-y-1">
        <span
          :title="title"
          class="min-w-0 text-heading-2 text-n-slate-12 line-clamp-1"
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
        class="text-sm text-n-slate-11 line-clamp-1 [&>p]:mb-0"
      />
      <CampaignMeta
        :is-live-chat-type="isLiveChatType"
        :status="status"
        :sender="sender"
        :inbox-name="inboxName"
        :inbox-icon="inboxIcon"
        :scheduled-at="scheduledAt"
        :audience="audience"
      />
    </div>

    <div class="flex items-center self-start justify-end gap-2 shrink-0">
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
        v-tooltip.top="t('CAMPAIGN.CARD.EDIT')"
        variant="faded"
        size="sm"
        color="slate"
        icon="i-lucide-sliders-vertical"
        :aria-label="t('CAMPAIGN.CARD.EDIT')"
        @click="emit('edit')"
      />
      <Button
        v-if="canCancel"
        v-tooltip.top="t('CAMPAIGN.CARD.CANCEL')"
        variant="faded"
        color="amber"
        size="sm"
        icon="i-lucide-circle-stop"
        :aria-label="t('CAMPAIGN.CARD.CANCEL')"
        @click="emit('cancel')"
      />
      <Button
        v-tooltip.top="t('CAMPAIGN.CARD.DELETE')"
        variant="faded"
        color="ruby"
        size="sm"
        icon="i-lucide-trash"
        :aria-label="t('CAMPAIGN.CARD.DELETE')"
        @click="emit('delete')"
      />
    </div>
  </CardLayout>
</template>
