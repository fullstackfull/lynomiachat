<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import TicketCompactList from './TicketCompactList.vue';
import TicketCreateDialog from './TicketCreateDialog.vue';
import { useLinkedSupportTickets } from 'dashboard/composables/useSupportTickets';

// The cases linked to the open conversation, and the one action that matters here: opening a case from what
// the agent is already looking at. The three links are prefilled from the conversation, because the agent has
// just answered "which customer" by being on this screen.
const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  contactId: {
    type: [Number, String],
    default: null,
  },
  inboxId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();

const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');

const createDialogRef = ref(null);

const params = computed(() => ({ conversation_id: props.conversationId }));

const { tickets, error, isLoading, hasLoadedOnce, isEmpty, load } =
  useLinkedSupportTickets(params);

const errorMessage = computed(() => {
  if (!error.value) return '';
  return (
    error.value.response?.data?.message ||
    t('SUPPORT_TICKETS.CONVERSATION_PANEL.ERROR')
  );
});

watch(() => props.conversationId, load);

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  load();
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <TicketCompactList
      :tickets="tickets"
      :is-loading="isLoading"
      :has-loaded-once="hasLoadedOnce"
      :is-empty="isEmpty"
      :error-message="errorMessage"
      :empty-message="t('SUPPORT_TICKETS.CONVERSATION_PANEL.EMPTY')"
    />

    <Button
      :label="t('SUPPORT_TICKETS.CONVERSATION_PANEL.NEW_CASE')"
      icon="i-lucide-plus"
      variant="faded"
      color="slate"
      size="sm"
      @click="createDialogRef?.open()"
    />

    <TicketCreateDialog
      ref="createDialogRef"
      :conversation-id="conversationId"
      :contact-id="contactId"
      :inbox-id="inboxId"
      :agents="agents"
      :teams="teams"
      @created="load"
    />
  </div>
</template>
