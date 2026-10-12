<script setup>
import { useI18n } from 'vue-i18n';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import StatusChip from './StatusChip.vue';

// One ticket in the portal's list. A card and not a table row: an account will ever have a handful of these,
// and the three readings that matter (what it is about, where it stands, whether Lynomia has replied) have to
// be legible on a phone (docs/platform-support/04-customer-ux.md §1).
defineProps({
  ticket: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
</script>

<template>
  <li class="list-none">
    <RouterLink
      :to="{
        name: 'platform_support_tickets_show',
        params: { ticketId: ticket.id },
      }"
      class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak bg-n-solid-1 hover:border-n-slate-6"
    >
      <div class="flex items-baseline justify-between gap-2">
        <span class="tabular-nums text-label-small text-n-slate-10">
          {{ ticket.reference }}
        </span>
        <time
          :title="
            t('PLATFORM_SUPPORT.LIST.LAST_ACTIVITY', {
              time: dynamicTime(ticket.last_activity_at),
            })
          "
          class="shrink-0 tabular-nums text-label-small text-n-slate-10"
        >
          {{ shortTimestamp(dynamicTime(ticket.last_activity_at), true) }}
        </time>
      </div>

      <div class="flex items-start gap-2 min-w-0">
        <!--
          The unread dot. Derived from the ticket's own columns rather than from a notification row, so it can
          never disagree with the thread below it (docs/platform-support/04-customer-ux.md §6).
        -->
        <span
          v-if="ticket.unread"
          data-test-id="platform-support-unread-dot"
          class="mt-1.5 size-2 shrink-0 rounded-full bg-n-brand"
          :aria-label="t('PLATFORM_SUPPORT.LIST.UNREAD')"
        />
        <h3
          class="m-0 break-words text-body-main text-n-slate-12"
          :class="{ 'font-medium': ticket.unread }"
        >
          {{ ticket.subject }}
        </h3>
      </div>

      <div class="flex flex-wrap items-center gap-1.5">
        <StatusChip kind="status" :value="ticket.status" />
        <StatusChip kind="category" :value="ticket.category" />
        <span
          v-if="ticket.message_count"
          class="inline-flex items-center gap-1 text-label-small text-n-slate-10"
        >
          {{ t('PLATFORM_SUPPORT.LIST.MESSAGES', { n: ticket.message_count }) }}
        </span>
      </div>
    </RouterLink>
  </li>
</template>
