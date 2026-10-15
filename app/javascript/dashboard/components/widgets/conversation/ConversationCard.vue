<script setup>
import { computed } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import UnreadBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);

// The one selection vocabulary this product uses, shared with the sidebar's active leaf: a 2px indigo rail
// at the inline start plus a tinted inset surface. Declared once so the two never drift apart.
const RAIL =
  "before:content-[''] before:absolute before:inset-y-2.5 before:ltr:left-0 before:rtl:right-0 before:w-0.5 before:rounded-full before:bg-lyn-indigo";

const unreadCount = computed(() => props.chat.unread_count);
const hasUnread = computed(() => unreadCount.value > 0);
const lastMessageInChat = computed(() => getLastMessage(props.chat));

const voiceCallData = computed(() => {
  const last = lastMessageInChat.value;
  if (last?.content_type !== 'voice_call' || !last.call) {
    return { status: null, direction: null };
  }
  return {
    status: last.call.status,
    direction: last.call.direction === 'outgoing' ? 'outbound' : 'inbound',
  };
});

const isAIAssignee = computed(() =>
  ['AgentBot', 'Captain::Assistant'].includes(props.chat?.meta?.assignee_type)
);

const hasSlaPolicyId = computed(
  () => props.chat?.applied_sla?.id && !props.currentContact?.blocked
);

const showAssigneeName = computed(
  () => props.showAssignee && Boolean(props.assignee.name)
);

// One quiet line under the preview carries what qualifies the conversation rather than names it: which
// inbox it arrived in and who owns it. It is skipped entirely when the conversation has neither, which is
// what keeps a plain row three lines tall.
const showMetaSection = computed(
  () => props.showInboxName || showAssigneeName.value
);

const showLabelsSection = computed(
  () => props.chat.labels?.length > 0 || hasSlaPolicyId.value
);

const messagePreviewClass = computed(() =>
  hasUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11'
);

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, props.inbox.id);
  } else {
    emit('deSelectConversation', props.chat.id, props.inbox.id);
  }
};

const selectedModel = computed({
  get: () => props.selected,
  set: value => onSelectConversation(value),
});
</script>

<template>
  <div
    class="conversation group relative flex items-start gap-3 cursor-pointer rounded-xl transition-colors duration-150 mx-2 my-0.5 py-2.5"
    :class="[
      {
        'active animate-card-select bg-lyn-indigo/[0.09] ring-1 ring-inset ring-lyn-indigo/30':
          isActiveChat,
        'selected bg-n-slate-3 ring-1 ring-inset ring-n-weak':
          selected && !isActiveChat,
        'hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3':
          !isActiveChat && !selected,
        'px-2': compact,
        'px-2.5': !compact,
      },
      isActiveChat ? RAIL : '',
    ]"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <Avatar
      v-if="!hideThumbnail"
      :name="currentContact.name"
      :src="currentContact.thumbnail"
      :size="36"
      :status="currentContact.availability_status"
      class="flex-shrink-0 mt-0.5"
      hide-offline-status
    >
      <template #overlay="{ size }">
        <!-- Revealed by hover, by keyboard focus, and always where there is no hover at all: gating it on a
             `mouseenter` left bulk selection with no path on a phone or a tablet, which render this card. -->
        <label
          class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px] opacity-0 group-hover:opacity-100 focus-within:opacity-100 [@media(hover:none)]:opacity-100"
          :class="{ '!opacity-100': selected }"
          :style="{ width: `${size}px`, height: `${size}px` }"
          @click.stop
        >
          <Checkbox
            v-model="selectedModel"
            :aria-label="
              $t('CHAT_LIST.SELECT_CONVERSATION', {
                name: currentContact.name,
              })
            "
          />
        </label>
      </template>
    </Avatar>

    <div class="flex flex-col flex-1 min-w-0 gap-1">
      <!-- Who, then how urgent, then when. The contact's name is the first thing read on the row. -->
      <div class="flex items-center min-w-0 gap-2">
        <h4
          dir="auto"
          class="conversation--user flex-1 min-w-0 my-0 text-sm truncate text-n-slate-12"
          :class="hasUnread ? 'font-semibold' : 'font-medium'"
        >
          {{ currentContact.name }}
        </h4>
        <CardPriorityIcon
          v-if="chat.priority"
          :priority="chat.priority"
          class="flex-shrink-0 !size-3.5"
        />
        <TimeAgo
          :last-activity-timestamp="chat.timestamp"
          :created-at-timestamp="chat.created_at"
          :conversation-id="chat.id"
          class="flex-shrink-0"
        />
      </div>

      <div class="flex items-center min-w-0 gap-2">
        <VoiceCallStatus
          v-if="voiceCallData.status"
          key="voice-status-row"
          :status="voiceCallData.status"
          :direction="voiceCallData.direction"
          :message-preview-class="messagePreviewClass"
          class="flex-1 min-w-0"
        />
        <MessagePreview
          v-else-if="lastMessageInChat"
          key="message-preview"
          :message="lastMessageInChat"
          class="flex-1 min-w-0 text-sm leading-5"
          :class="messagePreviewClass"
        />
        <p
          v-else
          key="no-messages"
          class="flex-1 min-w-0 my-0 overflow-hidden text-sm leading-5 whitespace-nowrap text-ellipsis"
          :class="messagePreviewClass"
        >
          <fluent-icon
            size="16"
            class="-mt-0.5 align-middle inline-block text-n-slate-10"
            icon="info"
          />
          <span class="mx-0.5">
            {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
          </span>
        </p>
        <UnreadBadge
          v-if="hasUnread"
          :count="unreadCount"
          class="flex-shrink-0"
        />
      </div>

      <div
        v-if="showMetaSection"
        class="flex items-center min-w-0 gap-2 pt-0.5"
      >
        <InboxName
          v-if="showInboxName"
          :inbox="inbox"
          class="flex-shrink min-w-0 max-w-[11rem]"
        />
        <span
          v-if="showAssigneeName"
          class="inline-flex items-center flex-shrink min-w-0 gap-1 text-xs font-medium text-n-slate-11"
        >
          <Icon
            :icon="isAIAssignee ? 'i-lucide-bot' : 'i-lucide-user-round'"
            class="flex-shrink-0 size-3 text-n-slate-10"
          />
          <span class="truncate">{{ assignee.name }}</span>
        </span>
      </div>

      <!-- Labels keep a line of their own: `CardLabels` decides how many chips fit from its container's
           width, so sharing a row with the inbox and the assignee is what makes it drop every chip for a
           bare overflow chevron. -->
      <CardLabels
        v-if="showLabelsSection"
        :conversation-labels="chat.labels || []"
        class="pt-0.5"
      >
        <template v-if="hasSlaPolicyId" #before>
          <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
        </template>
      </CardLabels>
    </div>
  </div>
</template>
