<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import EmptyState from 'dashboard/components-next/empty-state/EmptyState.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import DocsLink from 'dashboard/components-next/docs-link/DocsLink.vue';
import TicketCard from '../components/TicketCard.vue';
import TicketListSkeleton from '../components/TicketListSkeleton.vue';
import PlatformSupportAPI from '../platformSupportApi';
import { setPlatformSupportUnreadCount } from '../platformSupportStore';
import {
  PLATFORM_SUPPORT_CLOSED_STATUSES,
  PLATFORM_SUPPORT_PAGE_SIZE,
} from '../constants';

// "My tickets": the customer's own list of conversations with Lynomia.
//
// TWO GROUPINGS, NOT FILTERS. An account will ever have a handful of these, so Open and Closed as headed
// sections beat a filter bar that has to be learned (docs/platform-support/04-customer-ux.md §3.1). The page
// asks the server for one page of everything and groups what comes back; there is no status filter in the
// request, so the two sections always add up to what the server counted.

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountId, accountScopedRoute } = useAccount();
const { run } = useAbortableRequest();

const tickets = ref([]);
const meta = ref({
  currentPage: 1,
  totalEntries: 0,
  perPage: PLATFORM_SUPPORT_PAGE_SIZE,
});
const error = ref(null);
const isLoading = ref(false);
const hasLoadedOnce = ref(false);

const page = computed(() => Number(route.query.page) || 1);

const openTickets = computed(() =>
  tickets.value.filter(
    ticket => !PLATFORM_SUPPORT_CLOSED_STATUSES.includes(ticket.status)
  )
);
const closedTickets = computed(() =>
  tickets.value.filter(ticket =>
    PLATFORM_SUPPORT_CLOSED_STATUSES.includes(ticket.status)
  )
);

const isEmpty = computed(
  () => hasLoadedOnce.value && !error.value && tickets.value.length === 0
);

const totalPages = computed(() =>
  meta.value.perPage > 0
    ? Math.ceil(meta.value.totalEntries / meta.value.perPage)
    : 1
);

// A refused request carries the reason it was unusable; anything else gets the generic sentence rather than a
// raw error pushed at a customer.
const errorMessage = computed(() => {
  if (!error.value) return '';

  return (
    error.value.response?.data?.message ||
    t('PLATFORM_SUPPORT.ERROR.LIST_FAILED')
  );
});

const fetch = async () => {
  isLoading.value = true;
  error.value = null;

  try {
    const response = await run(
      signal =>
        PlatformSupportAPI.getTickets(
          { page: page.value, per_page: PLATFORM_SUPPORT_PAGE_SIZE },
          { signal }
        ),
      { onAbort: null }
    );
    if (response === null) return;

    tickets.value = response.data.payload || [];
    meta.value = {
      currentPage: Number(response.data.meta?.current_page) || 1,
      totalEntries: Number(response.data.meta?.total_entries) || 0,
      perPage:
        Number(response.data.meta?.per_page) || PLATFORM_SUPPORT_PAGE_SIZE,
    };
    setPlatformSupportUnreadCount(
      response.data.meta?.counts?.unread,
      accountId.value
    );
    hasLoadedOnce.value = true;
  } catch (requestError) {
    error.value = requestError;
    tickets.value = [];
  } finally {
    isLoading.value = false;
  }
};

const setPage = nextPage => {
  router.push({
    name: 'platform_support_tickets_index',
    query: { ...route.query, page: nextPage },
  });
  fetch();
};

onMounted(fetch);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="flex flex-col gap-3 px-4 pt-6 sm:px-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="flex flex-col gap-1 min-w-0">
          <h1 class="m-0 text-heading-1 text-n-slate-12">
            {{ t('PLATFORM_SUPPORT.LIST.HEADER') }}
          </h1>
          <p class="max-w-2xl m-0 text-body-main text-n-slate-11">
            {{ t('PLATFORM_SUPPORT.LIST.DESCRIPTION') }}
          </p>
        </div>
        <Button
          :label="t('PLATFORM_SUPPORT.LIST.NEW_TICKET')"
          icon="i-lucide-plus"
          size="sm"
          @click="
            router.push(accountScopedRoute('platform_support_tickets_new'))
          "
        />
      </div>
      <DocsLink
        article-key="contactLynomiaSupport"
        :label="t('PLATFORM_SUPPORT.DOCS.ABOUT_THE_DESK')"
      />
    </header>

    <main class="flex flex-col flex-1 gap-6 px-4 py-6 overflow-y-auto sm:px-6">
      <Banner v-if="errorMessage" color="ruby">{{ errorMessage }}</Banner>

      <TicketListSkeleton v-else-if="isLoading && !hasLoadedOnce" />

      <EmptyState
        v-else-if="isEmpty"
        icon="i-lucide-life-buoy"
        :title="t('PLATFORM_SUPPORT.LIST.EMPTY.TITLE')"
        :description="t('PLATFORM_SUPPORT.LIST.EMPTY.DESCRIPTION')"
      >
        <template #action>
          <div class="flex flex-col items-center gap-3">
            <p class="max-w-sm m-0 text-body-small text-n-slate-11">
              {{ t('PLATFORM_SUPPORT.LIST.EMPTY.NOT_FOR') }}
            </p>
            <Button
              :label="t('PLATFORM_SUPPORT.LIST.NEW_TICKET')"
              icon="i-lucide-plus"
              size="sm"
              @click="
                router.push(accountScopedRoute('platform_support_tickets_new'))
              "
            />
          </div>
        </template>
      </EmptyState>

      <template v-else>
        <section v-if="openTickets.length" class="flex flex-col gap-3">
          <h2 class="m-0 text-heading-3 text-n-slate-12">
            {{ t('PLATFORM_SUPPORT.LIST.OPEN_GROUP') }}
          </h2>
          <ul class="flex flex-col gap-3 p-0 m-0 list-none">
            <TicketCard
              v-for="ticket in openTickets"
              :key="ticket.id"
              :ticket="ticket"
            />
          </ul>
        </section>

        <section v-if="closedTickets.length" class="flex flex-col gap-3">
          <h2 class="m-0 text-heading-3 text-n-slate-12">
            {{ t('PLATFORM_SUPPORT.LIST.CLOSED_GROUP') }}
          </h2>
          <ul class="flex flex-col gap-3 p-0 m-0 list-none">
            <TicketCard
              v-for="ticket in closedTickets"
              :key="ticket.id"
              :ticket="ticket"
            />
          </ul>
        </section>
      </template>
    </main>

    <!-- Only past one page: a footer saying "1-3 of 3" is furniture. -->
    <PaginationFooter
      v-if="totalPages > 1"
      :current-page="meta.currentPage"
      :total-items="meta.totalEntries"
      :items-per-page="meta.perPage"
      @update:current-page="setPage"
    />
  </section>
</template>
