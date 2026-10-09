<script setup>
import { useI18n } from 'vue-i18n';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TicketEnumLabel from './TicketEnumLabel.vue';
import TicketSlaLabel from './TicketSlaLabel.vue';

// The cases linked to one record, for the panels that sit beside it. A table would not survive a 320px side
// panel, so each case is one stacked row: reference and subject, then the three readings an agent acts on.
defineProps({
  tickets: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  hasLoadedOnce: {
    type: Boolean,
    default: false,
  },
  isEmpty: {
    type: Boolean,
    default: false,
  },
  errorMessage: {
    type: String,
    default: '',
  },
  emptyMessage: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col gap-2">
    <Banner v-if="errorMessage" color="ruby">{{ errorMessage }}</Banner>

    <template v-else>
      <div
        v-if="isLoading && !hasLoadedOnce"
        class="flex items-center justify-center py-6 text-n-slate-11"
      >
        <Spinner />
      </div>

      <p
        v-else-if="isEmpty"
        class="py-4 m-0 text-center text-body-main text-n-slate-11"
      >
        {{ emptyMessage }}
      </p>

      <ul v-else class="flex flex-col m-0 list-none divide-y divide-n-weak">
        <li v-for="ticket in tickets" :key="ticket.id" class="py-2.5">
          <RouterLink
            :to="{
              name: 'support_tickets_show',
              params: { ticketId: ticket.id },
            }"
            class="flex flex-col gap-1.5"
          >
            <div class="flex items-baseline justify-between gap-2">
              <span class="tabular-nums text-label-small text-n-slate-10">
                {{ ticket.reference }}
              </span>
              <time
                :title="
                  t('SUPPORT_TICKETS.PANEL.LAST_ACTIVITY', {
                    time: dynamicTime(ticket.last_activity_at),
                  })
                "
                class="shrink-0 tabular-nums text-label-small text-n-slate-10"
              >
                {{ shortTimestamp(dynamicTime(ticket.last_activity_at), true) }}
              </time>
            </div>
            <span
              class="break-words text-body-main text-n-slate-12 hover:underline"
            >
              {{ ticket.title }}
            </span>
            <div class="flex flex-wrap items-center gap-1.5">
              <TicketEnumLabel kind="status" :value="ticket.status" />
              <TicketEnumLabel kind="priority" :value="ticket.priority" />
              <TicketSlaLabel :ticket="ticket" />
            </div>
          </RouterLink>
        </li>
      </ul>
    </template>
  </div>
</template>
