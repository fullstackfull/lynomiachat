<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { computed } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';

const { updateUISettings } = useUISettings();

const { uiSettings } = useUISettings();
const isContactSidebarOpen = computed(
  () => uiSettings.value.is_contact_sidebar_open
);

const handleConversationSidebarToggle = () => {
  updateUISettings({
    is_contact_sidebar_open: !isContactSidebarOpen.value,
    is_copilot_panel_open: false,
  });
};

const keyboardEvents = {
  'Alt+KeyO': {
    action: handleConversationSidebarToggle,
  },
};
useKeyboardEvents(keyboardEvents);
</script>

<template>
  <!-- This used to float over the message timeline on its own absolutely positioned pill. It now sits with
       the call button and the overflow menu, which is where every other conversation-level action lives. -->
  <Button
    v-tooltip.top="$t('CONVERSATION.SIDEBAR.CONTACT')"
    :aria-label="$t('CONVERSATION.SIDEBAR.CONTACT')"
    :aria-pressed="isContactSidebarOpen"
    ghost
    slate
    sm
    class="transition-colors duration-150"
    :class="{ 'bg-n-alpha-2 text-n-slate-12': isContactSidebarOpen }"
    icon="i-lucide-user-round"
    @click="handleConversationSidebarToggle"
  />
</template>
