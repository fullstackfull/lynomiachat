<script setup>
import { computed } from 'vue';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { useExactTimestamp } from 'shared/composables/useExactTimestamp';

import MessageStatus from './MessageStatus.vue';
import Icon from 'next/icon/Icon.vue';
import { useInbox } from 'dashboard/composables/useInbox';
import { useMessageContext } from './provider.js';

import { MESSAGE_STATUS, MESSAGE_TYPES } from './constants';

const exactTimestamp = useExactTimestamp();

const {
  isAFacebookInbox,
  isALineChannel,
  isAPIInbox,
  isASmsInbox,
  isATelegramChannel,
  isATwilioChannel,
  isAWebWidgetInbox,
  isAWhatsAppChannel,
  isAnEmailChannel,
  isAnInstagramChannel,
  isATiktokChannel,
} = useInbox();

const {
  status,
  isPrivate,
  createdAt,
  sourceId,
  messageType,
  contentAttributes,
} = useMessageContext();

// The day is stated once, on the separator above each day's run of messages, so repeating it on every
// stamp spent seven characters to say what the rule overhead already said -- and crowded the one part of
// this line that does change per message. `messageTimestamp` still escalates to a full 'LLL d y, h:mm a'
// for a message from another year, and the exact date and time stay in the hover tooltip below.
const readableTime = computed(() =>
  messageTimestamp(createdAt.value, 'h:mm a')
);

const exactTime = computed(() => exactTimestamp(createdAt.value));

const showStatusIndicator = computed(() => {
  if (isPrivate.value) return false;
  // Don't show status for failed messages, we already show error message
  if (status.value === MESSAGE_STATUS.FAILED) return false;
  // Don't show status for deleted messages
  if (contentAttributes.value?.deleted) return false;

  if (messageType.value === MESSAGE_TYPES.OUTGOING) return true;
  if (messageType.value === MESSAGE_TYPES.TEMPLATE) return true;

  return false;
});

const isSent = computed(() => {
  if (!showStatusIndicator.value) return false;

  // Messages will be marked as sent for the Email channel if they have a source ID.
  if (isAnEmailChannel.value) return !!sourceId.value;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isAFacebookInbox.value ||
    isASmsInbox.value ||
    isATelegramChannel.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.SENT;
  }

  // API inbox messages use real sent/delivered/read status values from the external system.
  if (isAPIInbox.value) return status.value === MESSAGE_STATUS.SENT;

  // All messages will be mark as sent for the Line channel, as there is no source ID.
  if (isALineChannel.value) return true;

  return false;
});

const isDelivered = computed(() => {
  if (!showStatusIndicator.value) return false;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isASmsInbox.value ||
    isAFacebookInbox.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.DELIVERED;
  }
  // API inbox messages use real delivered status from the external system.
  if (isAPIInbox.value) return status.value === MESSAGE_STATUS.DELIVERED;
  // All messages marked as delivered for the web widget inbox once they are sent.
  if (isAWebWidgetInbox.value) {
    return status.value === MESSAGE_STATUS.SENT;
  }
  if (isALineChannel.value) {
    return status.value === MESSAGE_STATUS.DELIVERED;
  }

  return false;
});

const isRead = computed(() => {
  if (!showStatusIndicator.value) return false;

  if (
    isAWhatsAppChannel.value ||
    isATwilioChannel.value ||
    isAFacebookInbox.value ||
    isAnInstagramChannel.value ||
    isATiktokChannel.value
  ) {
    return sourceId.value && status.value === MESSAGE_STATUS.READ;
  }

  if (isAWebWidgetInbox.value || isAPIInbox.value) {
    return status.value === MESSAGE_STATUS.READ;
  }

  return false;
});

const statusToShow = computed(() => {
  if (isRead.value) return MESSAGE_STATUS.READ;
  if (isDelivered.value) return MESSAGE_STATUS.DELIVERED;
  if (isSent.value) return MESSAGE_STATUS.SENT;
  // The SERVER saying the send is still in flight is the only thing that may render as "Sending". The
  // optimistic message the dashboard creates on send carries exactly this status (helper/commons.js), so the
  // clock still appears the moment an agent hits send.
  if (status.value === MESSAGE_STATUS.PROGRESS) return MESSAGE_STATUS.PROGRESS;

  // Nothing established a state. This used to fall through to PROGRESS, which is a claim: a spinning clock
  // says the product is still trying. A WhatsApp row whose status is `sent` but which has no source_id -- Meta
  // accepted it and the id was not stored -- sat there saying "Sending" forever. Unknown is what we know.
  return MESSAGE_STATUS.UNKNOWN;
});
</script>

<template>
  <div class="text-xs flex items-center gap-1.5">
    <div class="inline">
      <time
        v-tooltip.top="{
          content: exactTime,
          delay: { show: 500, hide: 0 },
        }"
        class="inline"
      >
        {{ readableTime }}
      </time>
    </div>
    <Icon v-if="isPrivate" icon="i-lucide-lock-keyhole" class="size-3" />
    <MessageStatus v-if="showStatusIndicator" :status="statusToShow" />
  </div>
</template>
`
