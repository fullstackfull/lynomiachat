<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useDebounceFn } from '@vueuse/core';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import EmptyState from 'dashboard/components-next/empty-state/EmptyState.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import TicketFilters from 'dashboard/components-next/SupportTickets/TicketFilters.vue';
import TicketViewTabs from 'dashboard/components-next/SupportTickets/TicketViewTabs.vue';
import TicketsTable from 'dashboard/components-next/SupportTickets/TicketsTable.vue';
import TicketCreateDialog from 'dashboard/components-next/SupportTickets/TicketCreateDialog.vue';
import { useSupportTicketList } from 'dashboard/composables/useSupportTickets';
import { TICKET_SEARCH_DEBOUNCE_DELAY } from 'dashboard/constants/supportTickets';

const ROUTE_NAME = 'support_tickets_index';

const { t } = useI18n();
const store = useStore();
const route = useRoute();

const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');

const createDialogRef = ref(null);

const {
  tickets,
  meta,
  counts,
  filters,
  error,
  isLoading,
  hasLoadedOnce,
  hasActiveFilters,
  isEmpty,
  fetch,
  updateFilters,
  setPage,
  setSort,
  setView,
  clearFilters,
} = useSupportTicketList(ROUTE_NAME);

const searchQuery = ref(route.query.q ?? '');
// The search term this page last put in the URL. Echoes of our own navigation must not overwrite a term the
// agent is still typing.
const pushedSearch = ref(searchQuery.value);

// A refused request carries the reason it was unusable; anything else gets the generic message rather than a
// raw error pushed at an agent.
const errorMessage = computed(() => {
  if (!error.value) return '';
  return (
    error.value.response?.data?.message || t('SUPPORT_TICKETS.ERROR.UNEXPECTED')
  );
});

const showEmptyState = computed(() => isEmpty.value && !isLoading.value);

const commitSearch = useDebounceFn(() => {
  const term = searchQuery.value.trim();
  if (term === pushedSearch.value) return;
  pushedSearch.value = term;
  updateFilters({ q: term || undefined });
}, TICKET_SEARCH_DEBOUNCE_DELAY);

watch(searchQuery, () => commitSearch());

watch(
  () => route.query.q,
  value => {
    const next = value ?? '';
    if (next === pushedSearch.value) return;
    pushedSearch.value = next;
    searchQuery.value = next;
  }
);

const onClearFilters = () => {
  pushedSearch.value = '';
  searchQuery.value = '';
  clearFilters();
};

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  fetch();
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="flex flex-col gap-4 px-6 pt-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="flex flex-col gap-1 min-w-0">
          <h1 class="text-heading-1 text-n-slate-12">
            {{ t('SUPPORT_TICKETS.HEADER') }}
          </h1>
          <p class="max-w-3xl mb-0 text-body-main text-n-slate-11">
            {{ t('SUPPORT_TICKETS.DESCRIPTION') }}
          </p>
        </div>
        <Button
          :label="t('SUPPORT_TICKETS.NEW_CASE')"
          icon="i-lucide-plus"
          size="sm"
          @click="createDialogRef?.open()"
        />
      </div>

      <TicketViewTabs :view="filters.view" :counts="counts" @change="setView" />

      <div class="flex flex-wrap items-center justify-between gap-3 min-w-0">
        <TicketFilters
          :filters="filters"
          :range="route.query.range"
          :agents="agents"
          :teams="teams"
          @update="updateFilters"
        />
        <div class="flex items-center gap-3">
          <Input
            v-model="searchQuery"
            :placeholder="t('SUPPORT_TICKETS.SEARCH_PLACEHOLDER')"
            class="group w-full sm:w-56 min-w-0 flex [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8"
            size="sm"
            type="search"
          >
            <template #prefix>
              <Icon
                icon="i-lucide-search"
                class="absolute top-1/2 -translate-y-1/2 text-n-slate-11 group-focus-within:text-n-brand size-3.5 ltr:left-2.5 rtl:right-2.5"
              />
            </template>
          </Input>
          <span
            v-if="meta.totalEntries"
            class="whitespace-nowrap text-body-main text-n-slate-11"
          >
            {{ t('SUPPORT_TICKETS.COUNT', { n: meta.totalEntries }) }}
          </span>
          <Button
            v-if="hasActiveFilters"
            :label="t('SUPPORT_TICKETS.FILTERS.CLEAR_ALL')"
            icon="i-lucide-x"
            slate
            ghost
            sm
            @click="onClearFilters"
          />
        </div>
      </div>
    </header>

    <main class="flex flex-col flex-1 min-h-0 px-6 pb-2 overflow-y-auto">
      <Banner v-if="errorMessage" class="mt-4" color="ruby">
        {{ errorMessage }}
      </Banner>

      <template v-else>
        <EmptyState
          v-if="showEmptyState"
          class="mt-4"
          icon="i-lucide-ticket"
          :title="
            hasActiveFilters
              ? t('SUPPORT_TICKETS.EMPTY.FILTERED_TITLE')
              : t('SUPPORT_TICKETS.EMPTY.TITLE')
          "
          :description="
            hasActiveFilters
              ? t('SUPPORT_TICKETS.EMPTY.FILTERED_DESCRIPTION')
              : t('SUPPORT_TICKETS.EMPTY.DESCRIPTION')
          "
        >
          <template #action>
            <Button
              v-if="hasActiveFilters"
              :label="t('SUPPORT_TICKETS.FILTERS.CLEAR_ALL')"
              icon="i-lucide-x"
              slate
              sm
              @click="onClearFilters"
            />
            <Button
              v-else
              :label="t('SUPPORT_TICKETS.NEW_CASE')"
              icon="i-lucide-plus"
              sm
              @click="createDialogRef?.open()"
            />
          </template>
        </EmptyState>

        <TicketsTable
          v-else
          :tickets="tickets"
          :loading="isLoading && !hasLoadedOnce"
          :sort="filters.sort"
          :agents="agents"
          :teams="teams"
          @sort="setSort"
        />
      </template>
    </main>

    <PaginationFooter
      v-if="meta.totalEntries"
      :current-page="meta.currentPage"
      :total-items="meta.totalEntries"
      :items-per-page="meta.perPage"
      @update:current-page="setPage"
    />

    <TicketCreateDialog
      ref="createDialogRef"
      :agents="agents"
      :teams="teams"
      @created="fetch"
    />
  </section>
</template>
