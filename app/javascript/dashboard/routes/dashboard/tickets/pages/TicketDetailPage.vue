<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import BackButton from 'dashboard/components/widgets/BackButton.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TicketDetailHeader from 'dashboard/components-next/SupportTickets/TicketDetailHeader.vue';
import TicketHistory from 'dashboard/components-next/SupportTickets/TicketHistory.vue';
import TicketSidePanel from 'dashboard/components-next/SupportTickets/TicketSidePanel.vue';
import { useSupportTicket } from 'dashboard/composables/useSupportTickets';
import { isTicketActive } from 'dashboard/helper/supportTicketHelper';

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');

const ticketId = computed(() => route.params.ticketId);

const {
  ticket,
  events,
  error,
  isLoading,
  isLoadingEvents,
  isSaving,
  hasMoreEvents,
  load,
  loadEvents,
  loadMoreEvents,
  save,
  addNote,
} = useSupportTicket(ticketId);

// Serialized with the case, so no second request resolves it.
const contactName = computed(() => ticket.value?.contact_name || '');

const errorMessage = computed(() => {
  if (!error.value) return '';
  return (
    error.value.response?.data?.message || t('SUPPORT_TICKETS.DETAIL.NOT_FOUND')
  );
});

const canAddNote = computed(() => isTicketActive(ticket.value));

// A refused change carries a message already written for a human -- a disallowed status transition names the
// attempted edge and the allowed set -- so it is shown as it came. The case is then reloaded, because a control
// bound to a value the server rejected would otherwise keep showing the operator's choice as if it had taken.
const applyUpdate = async attributes => {
  try {
    await save(attributes);
    useAlert(t('SUPPORT_TICKETS.DETAIL.UPDATE.SUCCESS'));
  } catch (updateError) {
    useAlert(
      updateError?.response?.data?.message ||
        t('SUPPORT_TICKETS.DETAIL.UPDATE.ERROR')
    );
    await load();
  }
};

const onAddNote = async body => {
  try {
    await addNote(body);
    useAlert(t('SUPPORT_TICKETS.DETAIL.NOTE.SUCCESS'));
  } catch (noteError) {
    useAlert(
      noteError?.response?.data?.message ||
        t('SUPPORT_TICKETS.DETAIL.NOTE.ERROR')
    );
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  load();
  loadEvents();
});
</script>

<template>
  <section
    class="flex flex-col w-full h-full px-6 py-6 overflow-y-auto bg-n-surface-1"
  >
    <div class="flex flex-col w-full max-w-6xl gap-6 mx-auto">
      <BackButton
        compact
        class="self-start"
        :back-url="{ name: 'support_tickets_index' }"
        :button-label="t('SUPPORT_TICKETS.DETAIL.BACK')"
      />

      <Banner v-if="errorMessage" color="ruby">{{ errorMessage }}</Banner>

      <div
        v-else-if="isLoading && !ticket"
        class="flex items-center justify-center py-20 text-n-slate-11"
      >
        <Spinner />
      </div>

      <template v-else-if="ticket">
        <TicketDetailHeader
          :ticket="ticket"
          :is-saving="isSaving"
          @update="applyUpdate"
        />

        <div
          class="grid grid-cols-1 gap-8 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]"
        >
          <div class="flex flex-col gap-6 min-w-0">
            <section class="flex flex-col gap-2">
              <h2 class="m-0 text-heading-2 text-n-slate-12">
                {{ t('SUPPORT_TICKETS.DETAIL.DESCRIPTION_TITLE') }}
              </h2>
              <p
                v-if="ticket.description"
                class="m-0 whitespace-pre-line break-words text-body-para text-n-slate-11"
              >
                {{ ticket.description }}
              </p>
              <p v-else class="m-0 text-body-main text-n-slate-10">
                {{ t('SUPPORT_TICKETS.DETAIL.NO_DESCRIPTION') }}
              </p>
            </section>

            <section class="flex flex-col gap-2">
              <h2 class="m-0 text-heading-2 text-n-slate-12">
                {{ t('SUPPORT_TICKETS.DETAIL.CONVERSATION.TITLE') }}
              </h2>
              <RouterLink
                v-if="ticket.conversation_display_id"
                :to="{
                  name: 'inbox_conversation',
                  params: { conversation_id: ticket.conversation_display_id },
                }"
                class="self-start text-body-main text-n-blue-11 hover:underline"
              >
                {{
                  t('SUPPORT_TICKETS.DETAIL.CONVERSATION.OPEN', {
                    id: ticket.conversation_display_id,
                  })
                }}
              </RouterLink>
              <p v-else class="m-0 text-body-main text-n-slate-10">
                {{ t('SUPPORT_TICKETS.DETAIL.CONVERSATION.NONE') }}
              </p>
            </section>

            <TicketHistory
              :events="events"
              :is-loading="isLoadingEvents"
              :has-more="hasMoreEvents"
              :is-saving="isSaving"
              :can-add-note="canAddNote"
              :agents="agents"
              :teams="teams"
              @load-more="loadMoreEvents"
              @add-note="onAddNote"
            />
          </div>

          <TicketSidePanel
            :ticket="ticket"
            :contact-name="contactName"
            :agents="agents"
            :teams="teams"
            :is-saving="isSaving"
            @update="applyUpdate"
          />
        </div>
      </template>
    </div>
  </section>
</template>
