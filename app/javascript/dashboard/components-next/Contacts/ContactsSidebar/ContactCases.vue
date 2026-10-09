<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import TicketCompactList from 'dashboard/components-next/SupportTickets/TicketCompactList.vue';
import { useLinkedSupportTickets } from 'dashboard/composables/useSupportTickets';

// This contact's support cases. The same list endpoint the workspace uses, filtered to the contact, so the
// server's visibility rule applies here too: an agent without `support_ticket_manage` sees the cases that are
// theirs, their team's, or that they opened, and nothing else.
const { t } = useI18n();
const route = useRoute();

const params = computed(() => ({ contact_id: route.params.contactId }));

const {
  tickets,
  totalEntries,
  error,
  isLoading,
  hasLoadedOnce,
  isEmpty,
  load,
} = useLinkedSupportTickets(params);

const errorMessage = computed(() => {
  if (!error.value) return '';
  return (
    error.value.response?.data?.message ||
    t('CONTACTS_LAYOUT.SIDEBAR.CASES.ERROR')
  );
});

// The panel shows the first page; the workspace is where the rest of them are.
const hasMore = computed(() => totalEntries.value > tickets.value.length);

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-3 px-6 pb-6">
    <TicketCompactList
      :tickets="tickets"
      :is-loading="isLoading"
      :has-loaded-once="hasLoadedOnce"
      :is-empty="isEmpty"
      :error-message="errorMessage"
      :empty-message="t('CONTACTS_LAYOUT.SIDEBAR.CASES.EMPTY_STATE')"
    />

    <Button
      v-if="hasMore"
      :label="t('CONTACTS_LAYOUT.SIDEBAR.CASES.VIEW_ALL')"
      variant="faded"
      color="slate"
      size="sm"
      @click="
        $router.push({
          name: 'support_tickets_index',
          query: { contact_id: route.params.contactId },
        })
      "
    />
  </div>
</template>
