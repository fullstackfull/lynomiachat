<script>
import { mapGetters } from 'vuex';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';

export default {
  components: {
    ChatList,
    ConversationBox,
    CmdBarConversationSnooze,
    SidepanelSwitch,
    ConversationSidebar,
  },
  beforeRouteLeave(to, from, next) {
    // Clear selected state if navigating away from a conversation to a route without a conversationId to prevent stale data issues
    // and resolves timing issues during navigation with conversation view and other screens
    if (this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
    next(); // Continue with navigation
  },
  props: {
    inboxId: {
      type: [String, Number],
      default: 0,
    },
    conversationId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    teamId: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
  },
  setup() {
    const { uiSettings, updateUISettings, isOnExpandedLayout } =
      useUISettings();
    const { accountId } = useAccount();

    return {
      uiSettings,
      updateUISettings,
      isOnExpandedLayout,
      accountId,
    };
  },
  data() {
    return {
      showSearchModal: false,
    };
  },
  computed: {
    ...mapGetters({
      chatList: 'getAllConversations',
      currentChat: 'getSelectedChat',
    }),
    showConversationList() {
      return this.isOnExpandedLayout ? !this.conversationId : true;
    },
    showMessageView() {
      return this.conversationId ? true : !this.isOnExpandedLayout;
    },
    shouldShowSidebar() {
      if (!this.currentChat.id) {
        return false;
      }

      const { is_contact_sidebar_open: isContactSidebarOpen } = this.uiSettings;
      return isContactSidebarOpen;
    },
  },
  watch: {
    conversationId() {
      this.fetchConversationIfUnavailable();
    },
  },

  created() {
    // Clear selected state early if no conversation is selected
    // This prevents child components from accessing stale data
    // and resolves timing issues during navigation
    // with conversation view and other screens
    if (!this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
  },

  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('portals/index');
    this.initialize();
    this.$watch('$store.state.route', () => this.initialize());
    this.$watch('chatList.length', () => {
      this.setActiveChat();
    });
  },

  methods: {
    onConversationLoad() {
      this.fetchConversationIfUnavailable();
    },
    initialize() {
      this.$store.dispatch('setActiveInbox', this.inboxId);
      this.setActiveChat();
    },
    toggleConversationLayout() {
      const { LAYOUT_TYPES } = wootConstants;
      const {
        conversation_display_type:
          conversationDisplayType = LAYOUT_TYPES.CONDENSED,
      } = this.uiSettings;
      const newViewType =
        conversationDisplayType === LAYOUT_TYPES.CONDENSED
          ? LAYOUT_TYPES.EXPANDED
          : LAYOUT_TYPES.CONDENSED;
      this.updateUISettings({
        conversation_display_type: newViewType,
        previously_used_conversation_display_type: newViewType,
      });
    },
    fetchConversationIfUnavailable() {
      if (!this.conversationId) {
        return;
      }
      const chat = this.findConversation();
      if (!chat) {
        this.$store.dispatch('getConversation', this.conversationId);
      }
    },
    findConversation() {
      const conversationId = parseInt(this.conversationId, 10);
      const [chat] = this.chatList.filter(c => c.id === conversationId);
      return chat;
    },
    setActiveChat() {
      if (this.conversationId) {
        const selectedConversation = this.findConversation();
        // If conversation doesn't exist or selected conversation is same as the active
        // conversation, don't set active conversation.
        if (
          !selectedConversation ||
          selectedConversation.id === this.currentChat.id
        ) {
          return;
        }
        const { messageId } = this.$route.query;
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
          });
      } else {
        this.$store.dispatch('clearSelectedState');
      }
    },
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
  },
};
</script>

<template>
  <section
    class="cw-dashboard-shell flex w-full h-full min-w-0 bg-n-background text-n-slate-12"
  >
    <div class="cw-dashboard-glow cw-dashboard-glow--one" />
    <div class="cw-dashboard-glow cw-dashboard-glow--two" />

    <ChatList
      class="cw-dashboard-panel cw-chat-list bg-n-background border-n-weak"
      :show-conversation-list="showConversationList"
      :conversation-inbox="inboxId"
      :label="label"
      :team-id="teamId"
      :conversation-type="conversationType"
      :folders-id="foldersId"
      :is-on-expanded-layout="isOnExpandedLayout"
      @conversation-load="onConversationLoad"
    />

    <ConversationBox
      v-if="showMessageView"
      class="cw-dashboard-panel cw-conversation-box bg-n-background border-n-weak"
      :inbox-id="inboxId"
      :is-on-expanded-layout="isOnExpandedLayout"
    >
      <SidepanelSwitch v-if="currentChat.id" />
    </ConversationBox>

    <Transition name="cw-sidebar-panel">
      <ConversationSidebar
        v-if="shouldShowSidebar"
        class="cw-dashboard-panel cw-contact-sidebar bg-n-background border-n-weak"
        :current-chat="currentChat"
      />
    </Transition>

    <CmdBarConversationSnooze />
  </section>
</template>

<style scoped>
/* =========================================================
   CHATWOOT CONVERSATION WORKSPACE - PREMIUM THEME v2
   Important: colours are inherited from Chatwoot semantic
   classes (bg-n-background / text-n-slate / border-n-weak),
   so the native Light/Dark switch remains authoritative.
========================================================= */

.cw-dashboard-shell {
  --cw-accent: #6366f1;
  --cw-accent-strong: #4f46e5;
  --cw-accent-soft: rgba(99, 102, 241, 0.1);
  --cw-border-hover: rgba(129, 140, 248, 0.38);
  --cw-shadow: 0 1px 2px rgba(15, 23, 42, 0.035),
    0 8px 24px rgba(15, 23, 42, 0.055);
  --cw-shadow-hover: 0 10px 24px rgba(15, 23, 42, 0.08),
    0 24px 50px rgba(15, 23, 42, 0.1);

  position: relative;
  isolation: isolate;
  gap: 10px;
  padding: 10px;
  overflow: visible;

  /* Do not set background-color here. Chatwoot's bg-n-background
     class handles light/dark mode automatically. */
  background-image: radial-gradient(
    circle at 78% -10%,
    rgba(99, 102, 241, 0.07),
    transparent 30rem
  );

  animation: cw-dashboard-enter 360ms cubic-bezier(0.22, 1, 0.36, 1);
}

/* Chatwoot puts the dark theme on an ancestor. We only alter
   decorative effects here; actual surfaces stay native tokens. */
:global(.dark) .cw-dashboard-shell,
:global(html.dark) .cw-dashboard-shell,
:global(body.dark) .cw-dashboard-shell {
  --cw-accent: #818cf8;
  --cw-accent-strong: #a5b4fc;
  --cw-accent-soft: rgba(99, 102, 241, 0.16);
  --cw-border-hover: rgba(129, 140, 248, 0.34);
  --cw-shadow: 0 1px 2px rgba(0, 0, 0, 0.22), 0 12px 28px rgba(0, 0, 0, 0.18);
  --cw-shadow-hover: 0 14px 30px rgba(0, 0, 0, 0.28),
    0 30px 60px rgba(0, 0, 0, 0.22);

  background-image: radial-gradient(
    circle at 78% -10%,
    rgba(99, 102, 241, 0.11),
    transparent 30rem
  );
}

/* =========================================================
   DECORATIVE GLOWS
========================================================= */

.cw-dashboard-glow {
  position: absolute;
  z-index: -1;
  pointer-events: none;
  border-radius: 999px;
  filter: blur(82px);
  opacity: 0.34;
  transition:
    opacity 300ms ease,
    transform 500ms cubic-bezier(0.22, 1, 0.36, 1);
}

.cw-dashboard-glow--one {
  top: -180px;
  right: 4%;
  width: 420px;
  height: 420px;
  background: rgba(99, 102, 241, 0.16);
}

.cw-dashboard-glow--two {
  bottom: -230px;
  left: 30%;
  width: 480px;
  height: 480px;
  background: rgba(129, 140, 248, 0.1);
}

.cw-dashboard-shell:hover .cw-dashboard-glow--one {
  transform: translate3d(-12px, 8px, 0) scale(1.03);
}

.cw-dashboard-shell:hover .cw-dashboard-glow--two {
  transform: translate3d(10px, -8px, 0) scale(1.02);
}

/* =========================================================
   PANELS
========================================================= */

.cw-dashboard-panel {
  position: relative;
  overflow: hidden;

  /* Background + border colours come from Chatwoot classes in
     the template. Never hard-code white here. */
  border-style: solid;
  border-width: 1px;
  border-radius: 16px;
  box-shadow: var(--cw-shadow);

  transition:
    border-color 200ms ease,
    box-shadow 260ms ease,
    transform 260ms cubic-bezier(0.22, 1, 0.36, 1);
}

.cw-dashboard-panel:hover {
  border-color: var(--cw-border-hover);
}

/* =========================================================
   CHAT LIST
========================================================= */

.cw-chat-list {
  z-index: 3;
  animation: cw-panel-left-enter 420ms cubic-bezier(0.22, 1, 0.36, 1) both;
  animation-delay: 35ms;
}

.cw-chat-list::after {
  content: '';
  position: absolute;
  top: 18px;
  right: 0;
  bottom: 18px;
  width: 1px;
  pointer-events: none;
  background: linear-gradient(
    to bottom,
    transparent,
    rgba(129, 140, 248, 0.22),
    transparent
  );
}

/* =========================================================
   CONVERSATION
========================================================= */

.cw-conversation-box {
  z-index: 2;
  flex: 1;
  min-width: 0;
  animation: cw-panel-main-enter 440ms cubic-bezier(0.22, 1, 0.36, 1) both;
  animation-delay: 70ms;
}

.cw-conversation-box:hover {
  border-color: var(--cw-border-hover);
  box-shadow: var(--cw-shadow-hover);
}

/* =========================================================
   CONTACT SIDEBAR
========================================================= */

.cw-contact-sidebar {
  z-index: 4;
  flex-shrink: 0;
  box-shadow: var(--cw-shadow);
}

.cw-contact-sidebar:hover {
  box-shadow: var(--cw-shadow-hover);
}

/* =========================================================
   IMPORTANT DARK-MODE FIX
   Do NOT make Chatwoot's bg-n-background transparent.
   Those semantic classes are exactly what switch child
   components between light and dark themes.
========================================================= */

.cw-dashboard-shell :deep(.border-n-weak) {
  transition: border-color 180ms ease;
}

/* =========================================================
   GOOD MORNING / WELCOME
   If the welcome component has cw-welcome-card, it gets the
   premium hover automatically while keeping its native theme.
========================================================= */

.cw-dashboard-shell :deep(.cw-welcome-card) {
  position: relative;
  overflow: hidden;
  border-radius: 18px;
  box-shadow: var(--cw-shadow);
  transform: translateZ(0);
  transition:
    transform 280ms cubic-bezier(0.22, 1, 0.36, 1),
    box-shadow 280ms ease,
    border-color 220ms ease;
}

.cw-dashboard-shell :deep(.cw-welcome-card::before) {
  content: '';
  position: absolute;
  top: -105px;
  right: -80px;
  width: 235px;
  height: 235px;
  pointer-events: none;
  border-radius: 999px;
  background: var(--cw-accent-soft);
  filter: blur(56px);
  opacity: 0.72;
  transition:
    transform 500ms ease,
    opacity 300ms ease;
}

.cw-dashboard-shell :deep(.cw-welcome-card::after) {
  content: '';
  position: absolute;
  top: -50%;
  left: -75%;
  width: 42%;
  height: 200%;
  pointer-events: none;
  transform: rotate(20deg);
  background: linear-gradient(
    90deg,
    transparent,
    rgba(129, 140, 248, 0.11),
    transparent
  );
  transition: left 650ms ease;
}

.cw-dashboard-shell :deep(.cw-welcome-card:hover) {
  transform: translateY(-4px);
  border-color: var(--cw-border-hover);
  box-shadow: var(--cw-shadow-hover);
}

.cw-dashboard-shell :deep(.cw-welcome-card:hover::before) {
  transform: scale(1.14) translate(-10px, 8px);
}

.cw-dashboard-shell :deep(.cw-welcome-card:hover::after) {
  left: 130%;
}

/* =========================================================
   FOUR FEATURE CARDS
========================================================= */

.cw-dashboard-shell :deep(.cw-feature-grid) {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
}

.cw-dashboard-shell :deep(.cw-feature-card) {
  position: relative;
  isolation: isolate;
  overflow: hidden;
  border-radius: 15px;
  box-shadow: var(--cw-shadow);
  transform: translateZ(0);
  transition:
    transform 260ms cubic-bezier(0.22, 1, 0.36, 1),
    box-shadow 260ms ease,
    border-color 220ms ease;
}

.cw-dashboard-shell :deep(.cw-feature-card::before) {
  content: '';
  position: absolute;
  top: 0;
  left: 18%;
  right: 18%;
  height: 2px;
  opacity: 0;
  background: linear-gradient(
    90deg,
    transparent,
    var(--cw-accent),
    transparent
  );
  transform: scaleX(0.55);
  transition:
    transform 260ms ease,
    opacity 260ms ease;
}

.cw-dashboard-shell :deep(.cw-feature-card::after) {
  content: '';
  position: absolute;
  z-index: -1;
  right: -45px;
  bottom: -55px;
  width: 135px;
  height: 135px;
  border-radius: 999px;
  background: var(--cw-accent-soft);
  filter: blur(34px);
  opacity: 0;
  transform: scale(0.72);
  transition:
    transform 320ms ease,
    opacity 320ms ease;
}

.cw-dashboard-shell :deep(.cw-feature-card:hover) {
  transform: translateY(-6px) scale(1.012);
  border-color: var(--cw-border-hover);
  box-shadow: var(--cw-shadow-hover);
}

.cw-dashboard-shell :deep(.cw-feature-card:hover::before) {
  opacity: 1;
  transform: scaleX(1);
}

.cw-dashboard-shell :deep(.cw-feature-card:hover::after) {
  opacity: 1;
  transform: scale(1.15);
}

.cw-dashboard-shell :deep(.cw-feature-icon) {
  transition:
    transform 300ms cubic-bezier(0.34, 1.56, 0.64, 1),
    filter 220ms ease;
}

.cw-dashboard-shell :deep(.cw-feature-card:hover .cw-feature-icon) {
  transform: translateY(-2px) rotate(-4deg) scale(1.08);
  filter: drop-shadow(0 8px 14px rgba(99, 102, 241, 0.18));
}

/* =========================================================
   SCROLLBARS
========================================================= */

.cw-dashboard-shell :deep(*) {
  scrollbar-width: thin;
  scrollbar-color: rgba(148, 163, 184, 0.34) transparent;
}

.cw-dashboard-shell :deep(*::-webkit-scrollbar) {
  width: 5px;
  height: 5px;
}

.cw-dashboard-shell :deep(*::-webkit-scrollbar-track) {
  background: transparent;
}

.cw-dashboard-shell :deep(*::-webkit-scrollbar-thumb) {
  background: rgba(148, 163, 184, 0.32);
  border-radius: 999px;
}

.cw-dashboard-shell :deep(*::-webkit-scrollbar-thumb:hover) {
  background: rgba(100, 116, 139, 0.48);
}

/* =========================================================
   CONTACT SIDEBAR TRANSITION
========================================================= */

.cw-sidebar-panel-enter-active,
.cw-sidebar-panel-leave-active {
  transition:
    opacity 220ms ease,
    transform 260ms cubic-bezier(0.22, 1, 0.36, 1);
}

.cw-sidebar-panel-enter-from,
.cw-sidebar-panel-leave-to {
  opacity: 0;
  transform: translateX(16px);
}

/* =========================================================
   PAGE ANIMATIONS
========================================================= */

@keyframes cw-dashboard-enter {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

@keyframes cw-panel-left-enter {
  from {
    opacity: 0;
    transform: translateX(-10px);
  }
  to {
    opacity: 1;
    transform: translateX(0);
  }
}

@keyframes cw-panel-main-enter {
  from {
    opacity: 0;
    transform: translateY(7px) scale(0.997);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

/* =========================================================
   RESPONSIVE
========================================================= */

@media (max-width: 1200px) {
  .cw-dashboard-shell :deep(.cw-feature-grid) {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 1024px) {
  .cw-dashboard-shell {
    gap: 6px;
    padding: 6px;
  }

  .cw-dashboard-panel {
    border-radius: 13px;
  }
}

@media (max-width: 767px) {
  .cw-dashboard-shell {
    gap: 0;
    padding: 0;
    background-image: none;
  }

  .cw-dashboard-panel {
    border: 0;
    border-radius: 0;
    box-shadow: none;
  }

  .cw-dashboard-glow {
    display: none;
  }

  .cw-dashboard-shell :deep(.cw-feature-grid) {
    grid-template-columns: 1fr;
  }

  .cw-dashboard-shell :deep(.cw-feature-card:hover),
  .cw-dashboard-shell :deep(.cw-welcome-card:hover) {
    transform: none;
  }
}

/* =========================================================
   ACCESSIBILITY
========================================================= */

@media (prefers-reduced-motion: reduce) {
  .cw-dashboard-shell,
  .cw-chat-list,
  .cw-conversation-box,
  .cw-dashboard-panel,
  .cw-dashboard-glow,
  .cw-dashboard-shell :deep(.cw-welcome-card),
  .cw-dashboard-shell :deep(.cw-feature-card),
  .cw-dashboard-shell :deep(.cw-feature-icon),
  .cw-sidebar-panel-enter-active,
  .cw-sidebar-panel-leave-active {
    animation: none !important;
    transition: none !important;
  }
}
</style>
