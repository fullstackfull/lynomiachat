<script setup>
import { ref, computed, provide } from 'vue';
import { Virtualizer } from 'virtua/vue';
import { useBreakpoints } from '@vueuse/core';
import { useChatListKeyboardEvents } from 'dashboard/composables/chatlist/useChatListKeyboardEvents';
import ConversationItem from './ConversationItem.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';
import { Skeleton } from 'dashboard/components-next/skeleton';

import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  conversationList: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  showEndOfListMessage: { type: Boolean, default: false },
  label: { type: String, default: '' },
  teamId: { type: [String, Number], default: 0 },
  foldersId: { type: [String, Number], default: 0 },
  conversationType: { type: String, default: '' },
  showAssignee: { type: Boolean, default: false },
  isOnExpandedLayout: { type: Boolean, default: false },
});

const emit = defineEmits(['loadMore']);

const conversationListRef = ref(null);
const virtualListRef = ref(null);
const isContextMenuOpen = ref(false);

provide('contextMenuElementTarget', virtualListRef);

const breakpoints = useBreakpoints({
  lg: wootConstants.LARGE_SCREEN_BREAKPOINT,
});
const isLgScreen = breakpoints.greaterOrEqual('lg');
const showExpandedCards = computed(
  () => props.isOnExpandedLayout && isLgScreen.value
);

useChatListKeyboardEvents(conversationListRef);

const intersectionObserverOptions = computed(() => ({
  root: conversationListRef.value,
  rootMargin: '100px 0px 100px 0px',
}));

const onContextMenuToggle = state => {
  isContextMenuOpen.value = state;
};

const loadMoreConversations = () => {
  emit('loadMore');
};

provide('toggleContextMenu', onContextMenuToggle);

defineExpose({ conversationListRef });
</script>

<template>
  <div
    ref="conversationListRef"
    class="flex-1 min-h-0 overflow-y-auto conversations-list"
    :class="{ '!overflow-hidden': isContextMenuOpen }"
  >
    <!-- The first fetch used to show a blank panel with one spinner pinned to the bottom. These rows are
         `aria-hidden` and deliberately do NOT carry the `conversation` class: `div.conversations-list
         div.conversation` is a load-bearing selector for Alt+J / Alt+K and for resolve-and-next, and a
         placeholder answering it would silently make those keys navigate to nothing. -->
    <div
      v-if="isLoading && !conversationList.length"
      class="flex flex-col"
      aria-hidden="true"
    >
      <div
        v-for="row in 6"
        :key="`conversation-skeleton-${row}`"
        class="flex items-start gap-2 px-3 py-3 border-b border-n-slate-3"
      >
        <Skeleton width="w-8" height="h-8" shape="circle" />
        <div class="flex flex-col flex-1 gap-2 min-w-0 pt-1">
          <Skeleton width="w-24" height="h-3" />
          <Skeleton width="w-full" height="h-3" />
        </div>
      </div>
    </div>
    <Virtualizer
      ref="virtualListRef"
      v-slot="{ item }"
      :data="conversationList"
      class="[&>div:has(+_div_.active)>*]:!border-n-surface-1 [&>div:has(+_div_.selected)>*]:!border-n-surface-1"
    >
      <ConversationItem
        :source="item"
        :label="label"
        :team-id="teamId"
        :folders-id="foldersId"
        :conversation-type="conversationType"
        :show-assignee="showAssignee"
        :show-expanded="showExpandedCards"
      />
    </Virtualizer>
    <div
      v-if="isLoading && conversationList.length"
      class="flex justify-center my-4"
    >
      <Spinner class="text-n-brand" />
    </div>
    <p
      v-else-if="!isLoading && showEndOfListMessage"
      class="p-4 text-center text-n-slate-11"
    >
      {{ $t('CHAT_LIST.EOF') }}
    </p>
    <IntersectionObserver
      v-else-if="!isLoading"
      :options="intersectionObserverOptions"
      @observed="loadMoreConversations"
    />
  </div>
</template>
