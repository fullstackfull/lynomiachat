<script>
import { mapGetters } from 'vuex';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
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
    const { uiSettings, isOnExpandedLayout } = useUISettings();
    const { accountId } = useAccount();

    return {
      uiSettings,
      isOnExpandedLayout,
      accountId,
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
  },
};
</script>

<template>
  <!-- One shell, three panels. Padding, radius, elevation and the panel order come from the design system's
       own spacing, radius, shadow and z-index scales; the previous bespoke indigo palette, decorative glow
       layers and `:deep(*)` scrollbar override lived only here and did not follow the brand token. -->
  <section
    class="relative isolate flex w-full h-full min-w-0 gap-0 p-0 md:gap-1.5 md:p-1.5 lg:gap-2.5 lg:p-2.5 bg-n-background text-n-slate-12 [scrollbar-width:thin]"
  >
    <ChatList
      class="relative z-20 overflow-hidden border-0 md:border md:border-n-weak md:rounded-overlay lg:rounded-2xl md:shadow-raised transition-colors duration-200 md:hover:border-n-brand/30 motion-safe:animate-fade-in-up bg-n-background"
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
      class="relative z-10 flex-1 min-w-0 overflow-hidden border-0 md:border md:border-n-weak md:rounded-overlay lg:rounded-2xl md:shadow-raised transition-[border-color,box-shadow] duration-200 md:hover:border-n-brand/30 md:hover:shadow-overlay motion-safe:animate-fade-in-up bg-n-background"
      :inbox-id="inboxId"
      :is-on-expanded-layout="isOnExpandedLayout"
    >
      <SidepanelSwitch v-if="currentChat.id" />
    </ConversationBox>

    <!-- The slide used a physical `translateX`, so in Arabic the panel entered from the wrong edge. -->
    <Transition
      enter-active-class="transition-[opacity,transform] duration-200 ease-out motion-reduce:transition-none"
      enter-from-class="opacity-0 ltr:translate-x-4 rtl:-translate-x-4"
      leave-active-class="transition-[opacity,transform] duration-200 ease-out motion-reduce:transition-none"
      leave-to-class="opacity-0 ltr:translate-x-4 rtl:-translate-x-4"
    >
      <ConversationSidebar
        v-if="shouldShowSidebar"
        class="relative z-30 flex-shrink-0 overflow-hidden border-0 md:border md:border-n-weak md:rounded-overlay lg:rounded-2xl md:shadow-raised transition-[border-color,box-shadow] duration-200 md:hover:shadow-overlay bg-n-background"
        :current-chat="currentChat"
      />
    </Transition>

    <CmdBarConversationSnooze />
  </section>
</template>
