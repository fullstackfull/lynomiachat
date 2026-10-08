<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import AuditLogFilters from './components/AuditLogFilters.vue';
import {
  generateTranslationPayload,
  generateLogActionKey,
  auditLogFiltersFromQuery,
  buildAuditLogRouteQuery,
} from 'dashboard/helper/auditlogHelper';

const SEARCH_DEBOUNCE_DELAY = 500;
const MIN_SEARCH_LENGTH = 3;

const getters = useStoreGetters();
const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const records = computed(() => getters['auditlogs/getAuditLogs'].value);
const uiFlags = computed(() => getters['auditlogs/getUIFlags'].value);
const meta = computed(() => getters['auditlogs/getMeta'].value);
const agentList = computed(() => getters['agents/getAgents'].value);

const searchQuery = ref(route.query.q ?? '');
// The search term this page last put in the URL. Echoes of our own navigation
// must not overwrite a term the admin is still typing.
const pushedSearch = ref(searchQuery.value);

const filters = computed(() => auditLogFiltersFromQuery(route.query));

const hasActiveFilters = computed(() => {
  const { q, types, since, sort } = filters.value;
  return Boolean(q || types || since || sort);
});

const fetchAuditLogs = async () => {
  try {
    await store.dispatch('auditlogs/fetch', filters.value);
  } catch (error) {
    const errorMessage = error?.message || t('AUDIT_LOGS.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const updateQuery = partial => {
  // a debounced search can land after the admin has moved to another page
  if (route.name !== 'auditlogs_list') return;
  router.push({
    name: 'auditlogs_list',
    query: buildAuditLogRouteQuery({ ...route.query, ...partial }),
  });
};

const onFiltersUpdate = partial => {
  updateQuery({ ...partial, page: undefined });
};

const onPageChange = page => {
  updateQuery({ page });
};

// The time column is already sortable through the filter bar; the heading drives the same query
// parameter, so the two controls can never disagree.
const onSortChange = ({ order }) => {
  onFiltersUpdate({ sort: order === 'asc' ? 'asc' : undefined });
};

const clearFilters = () => {
  pushedSearch.value = '';
  searchQuery.value = '';
  router.push({ name: 'auditlogs_list', query: {} });
};

const generateLogText = auditLogItem => {
  const payload = generateTranslationPayload(auditLogItem, agentList.value);
  const translationKey = generateLogActionKey(auditLogItem);

  const joinIfArray = value => {
    return Array.isArray(value) ? value.join(', ') : value;
  };

  const mergedPayload = {
    ...payload,
    attributes: joinIfArray(payload.attributes),
    values: joinIfArray(payload.values),
  };
  return t(translationKey, mergedPayload);
};

// Chatwoot's Enterprise audit log resolved each row's IP to a city and country through an Enterprise
// job and showed that under a "Location" heading. Lynomia runs no such job, so `city` and `country`
// stay null and the column is always the address itself -- masked, unless the account has
// `audit_log_ip_address` on, which the server honours.
const tableHeaders = computed(() => {
  return [
    t('AUDIT_LOGS.LIST.TABLE_HEADER.ACTIVITY'),
    t('AUDIT_LOGS.LIST.TABLE_HEADER.TIME'),
    t('AUDIT_LOGS.LIST.TABLE_HEADER.IP_ADDRESS'),
  ];
});

const commitSearch = useDebounceFn(() => {
  const typed = searchQuery.value.trim();
  const term = typed.length < MIN_SEARCH_LENGTH ? '' : typed;
  if (term === pushedSearch.value) return;
  pushedSearch.value = term;
  onFiltersUpdate({ q: term || undefined });
}, SEARCH_DEBOUNCE_DELAY);

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

watch(
  () => route.query,
  () => {
    if (route.name === 'auditlogs_list') fetchAuditLogs();
  }
);

onMounted(() => {
  store.dispatch('agents/get');
  fetchAuditLogs();
});
</script>

<template>
  <SettingsLayout
    :no-records-found="!records.length && !uiFlags.fetchingList"
    :no-records-message="
      hasActiveFilters ? $t('AUDIT_LOGS.SEARCH_404') : $t('AUDIT_LOGS.LIST.404')
    "
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('AUDIT_LOGS.HEADER')"
        :description="$t('AUDIT_LOGS.DESCRIPTION')"
        :link-text="$t('AUDIT_LOGS.LEARN_MORE')"
        :search-placeholder="$t('AUDIT_LOGS.FILTERS.SEARCH_PLACEHOLDER')"
        feature-name="audit_logs"
      >
        <template #tabs>
          <AuditLogFilters
            :type="filters.types?.[0]"
            :range="route.query.range"
            :since="filters.since"
            :until="filters.until"
            :sort="filters.sort"
            @update="onFiltersUpdate"
          />
        </template>
        <template v-if="meta.totalEntries" #count>
          <span class="text-body-main text-n-slate-11 whitespace-nowrap">
            {{ $t('AUDIT_LOGS.COUNT', { n: meta.totalEntries }) }}
          </span>
        </template>
        <template v-if="hasActiveFilters" #actions>
          <Button
            :label="$t('AUDIT_LOGS.FILTERS.CLEAR_ALL')"
            icon="i-lucide-x"
            slate
            ghost
            sm
            @click="clearFilters"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <div class="flex flex-col">
        <BaseTable
          sticky-header
          :headers="tableHeaders"
          :items="records"
          :loading="uiFlags.fetchingList"
          :loading-message="$t('AUDIT_LOGS.LOADING')"
          :loading-rows="8"
          :column-classes="['', '', 'hidden sm:table-cell']"
          :sortable-columns="[null, 'created_at', null]"
          sort-by="created_at"
          :sort-order="filters.sort === 'asc' ? 'asc' : 'desc'"
          @sort="onSortChange"
        >
          <template #row="{ items }">
            <BaseTableRow
              v-for="auditLogItem in items"
              :key="auditLogItem.id"
              :item="auditLogItem"
            >
              <template #default>
                <BaseTableCell>
                  <span
                    class="text-body-main text-n-slate-12 whitespace-nowrap"
                  >
                    {{ generateLogText(auditLogItem) }}
                  </span>
                </BaseTableCell>

                <BaseTableCell>
                  <span
                    class="text-body-main text-n-slate-11 whitespace-nowrap"
                  >
                    {{
                      messageTimestamp(
                        auditLogItem.created_at,
                        'MMM dd, yyyy hh:mm a'
                      )
                    }}
                  </span>
                </BaseTableCell>

                <BaseTableCell class="w-36 hidden sm:table-cell">
                  <span class="text-body-main text-n-slate-11">
                    {{ auditLogItem.remote_address }}
                  </span>
                </BaseTableCell>
              </template>
            </BaseTableRow>
          </template>
        </BaseTable>
        <PaginationFooter
          :current-page="Number(meta.currentPage)"
          :total-items="meta.totalEntries"
          :items-per-page="meta.perPage"
          class="!px-0"
          @update:current-page="onPageChange"
        />
      </div>
    </template>
  </SettingsLayout>
</template>
