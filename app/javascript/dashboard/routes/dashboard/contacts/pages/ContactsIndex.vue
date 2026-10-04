<script setup>
import { onMounted, computed, ref, reactive, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { debounce } from '@chatwoot/utils';
import { useUISettings } from 'dashboard/composables/useUISettings';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';

import ContactsListLayout from 'dashboard/components-next/Contacts/ContactsListLayout.vue';
import ContactEmptyState from 'dashboard/components-next/Contacts/EmptyState/ContactEmptyState.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactsList from 'dashboard/components-next/Contacts/Pages/ContactsList.vue';
import ContactsBulkActionBar from '../components/ContactsBulkActionBar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import BulkActionsAPI from 'dashboard/api/bulkActions';
import { waitForBulkActionCompletion } from 'dashboard/helper/bulkActionCompletion';

// Only order backed by index_contacts_on_account_id_and_last_activity_at
const DEFAULT_SORT = '-last_activity_at';
const DEBOUNCE_DELAY = 300;

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const { updateUISettings, uiSettings } = useUISettings();

const contacts = useMapGetter('contacts/getContactsList');
const uiFlags = useMapGetter('contacts/getUIFlags');
const customViewsUiFlags = useMapGetter('customViews/getUIFlags');
const segments = useMapGetter('customViews/getContactCustomViews');
const appliedFilters = useMapGetter('contacts/getAppliedContactFilters');
const meta = useMapGetter('contacts/getMeta');

const searchQuery = computed(() => route.query?.search);
const searchValue = ref(searchQuery.value || '');
const pageNumber = computed(() => Number(route.query?.page) || 1);
// For infinite scroll in search, track page internally
const searchPageNumber = ref(1);
const isLoadingMore = ref(false);

const parseSortSettings = (sortString = '') => {
  const sortValue = sortString || DEFAULT_SORT;
  const hasDescending = sortValue.startsWith('-');
  return {
    sort: hasDescending ? sortValue.slice(1) : sortValue,
    order: hasDescending ? '-' : '',
  };
};

const { contacts_sort_by: contactSortBy = '' } = uiSettings.value ?? {};
const { sort: initialSort, order: initialOrder } =
  parseSortSettings(contactSortBy);

const sortState = reactive({
  activeSort: initialSort,
  activeOrdering: initialOrder,
});

const activeLabel = computed(() => route.params.label);
const activeSegmentId = computed(() => route.params.segmentId);
const isFetchingList = computed(
  () => uiFlags.value.isFetching || customViewsUiFlags.value.isFetching
);
const currentPage = computed(() => Number(meta.value?.currentPage));
const totalItems = computed(() => meta.value?.count);
const hasMore = computed(() => meta.value?.hasMore ?? false);
const isSearchView = computed(() => !!searchQuery.value);

const selectedContactIds = ref([]);
// Set only by the bar's "select all N in this view". The ids then stop being the target: the server resolves
// the view itself, because the browser is holding one page of it (docs/contacts/10-phase-d.md §D4).
const isWholeViewSelected = ref(false);
const isBulkActionLoading = ref(false);
const bulkDeleteDialogRef = ref(null);
const selectedCount = computed(() =>
  isWholeViewSelected.value
    ? (totalItems.value ?? selectedContactIds.value.length)
    : selectedContactIds.value.length
);
const bulkDeleteDialogTitle = computed(() =>
  selectedCount.value > 1
    ? t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.TITLE')
    : t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.SINGULAR_TITLE')
);
const bulkDeleteDialogDescription = computed(() =>
  selectedCount.value > 1
    ? t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.DESCRIPTION', {
        count: selectedCount.value,
      })
    : t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.SINGULAR_DESCRIPTION')
);
const bulkDeleteDialogConfirmLabel = computed(() =>
  selectedCount.value > 1
    ? t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.CONFIRM_MULTIPLE')
    : t('CONTACTS_BULK_ACTIONS.DELETE_DIALOG.CONFIRM_SINGLE')
);
const hasSelection = computed(() => selectedCount.value > 0);
const activeSegment = computed(() => {
  if (!activeSegmentId.value) return undefined;
  return segments.value.find(view => view.id === Number(activeSegmentId.value));
});

const hasContacts = computed(() => contacts.value.length > 0);
const isContactIndexView = computed(
  () => route.name === 'contacts_dashboard_index' && pageNumber.value === 1
);
const isActiveView = computed(() => route.name === 'contacts_dashboard_active');
const hasAppliedFilters = computed(() => {
  return appliedFilters.value.length > 0;
});

const showEmptyStateLayout = computed(() => {
  return (
    !searchQuery.value &&
    !hasContacts.value &&
    isContactIndexView.value &&
    !hasAppliedFilters.value
  );
});
const showEmptyText = computed(() => {
  return (
    (searchQuery.value ||
      hasAppliedFilters.value ||
      !isContactIndexView.value) &&
    !hasContacts.value
  );
});

const headerTitle = computed(() => {
  if (searchQuery.value) return t('CONTACTS_LAYOUT.HEADER.SEARCH_TITLE');
  if (isActiveView.value) return t('CONTACTS_LAYOUT.HEADER.ACTIVE_TITLE');
  if (activeSegmentId.value) return activeSegment.value?.name;
  if (activeLabel.value) return `#${activeLabel.value}`;
  return t('CONTACTS_LAYOUT.HEADER.TITLE');
});

const emptyStateMessage = computed(() => {
  if (isActiveView.value)
    return t('CONTACTS_LAYOUT.EMPTY_STATE.ACTIVE_EMPTY_STATE_TITLE');
  if (!searchQuery.value || hasAppliedFilters.value)
    return t('CONTACTS_LAYOUT.EMPTY_STATE.LIST_EMPTY_STATE_TITLE');
  return t('CONTACTS_LAYOUT.EMPTY_STATE.SEARCH_EMPTY_STATE_TITLE');
});

const visibleContactIds = computed(() =>
  contacts.value.map(contact => contact.id)
);

const clearSelection = () => {
  selectedContactIds.value = [];
  isWholeViewSelected.value = false;
};

const selectAllMatching = () => {
  isWholeViewSelected.value = true;
};

const openBulkDeleteDialog = () => {
  if (!selectedContactIds.value.length || isBulkActionLoading.value) return;
  bulkDeleteDialogRef.value?.open?.();
};

const toggleSelectAll = shouldSelect => {
  // Any hand-made change to the selection means it is no longer "everything this view matches".
  isWholeViewSelected.value = false;
  const currentSelection = new Set(selectedContactIds.value);
  if (shouldSelect) {
    visibleContactIds.value.forEach(id => currentSelection.add(id));
  } else {
    visibleContactIds.value.forEach(id => currentSelection.delete(id));
  }
  selectedContactIds.value = Array.from(currentSelection);
};

const toggleContactSelection = ({ id, value }) => {
  isWholeViewSelected.value = false;
  const isAlreadySelected = selectedContactIds.value.includes(id);
  const shouldSelect = value ?? !isAlreadySelected;

  if (shouldSelect && !isAlreadySelected) {
    selectedContactIds.value = [...selectedContactIds.value, id];
  } else if (!shouldSelect && isAlreadySelected) {
    selectedContactIds.value = selectedContactIds.value.filter(
      contactId => contactId !== id
    );
  }
};

const updatePageParam = (page, search = '') => {
  const query = {
    ...route.query,
    page: page.toString(),
    ...(search ? { search } : {}),
  };

  if (!search) {
    delete query.search;
  }

  router.replace({ query });
};

const buildSortAttr = () =>
  `${sortState.activeOrdering}${sortState.activeSort}`;

const getCommonFetchParams = (page = 1) => ({
  page,
  sortAttr: buildSortAttr(),
  label: activeLabel.value,
});

const fetchContacts = async (page = 1, options = {}) => {
  const { clearSelection: shouldClearSelection = true } = options;
  if (shouldClearSelection) {
    clearSelection();
  }
  await store.dispatch('contacts/clearContactFilters');
  await store.dispatch('contacts/get', getCommonFetchParams(page));
  updatePageParam(page);
};

const fetchSavedOrAppliedFilteredContact = async (
  payload,
  page = 1,
  options = {}
) => {
  if (!activeSegmentId.value && !hasAppliedFilters.value) return;

  const { clearSelection: shouldClearSelection = true } = options;
  if (shouldClearSelection) {
    clearSelection();
  }

  await store.dispatch('contacts/filter', {
    ...getCommonFetchParams(page),
    queryPayload: payload,
  });
  updatePageParam(page);
};

const fetchActiveContacts = async (page = 1, options = {}) => {
  const { clearSelection: shouldClearSelection = true } = options;
  if (shouldClearSelection) {
    clearSelection();
  }

  await store.dispatch('contacts/clearContactFilters');
  await store.dispatch('contacts/active', {
    page,
    sortAttr: buildSortAttr(),
  });
  updatePageParam(page);
};

const searchContacts = debounce(
  async (value, page = 1, append = false, options = {}) => {
    const { clearSelection: shouldClearSelection = true } = options;

    if (!append) {
      searchPageNumber.value = 1;

      if (shouldClearSelection) {
        clearSelection();
      }
    }
    await store.dispatch('contacts/clearContactFilters');
    searchValue.value = value;

    if (!value) {
      updatePageParam(page);
      await fetchContacts(page, { clearSelection: false });
      return;
    }

    updatePageParam(page, value);
    await store.dispatch('contacts/search', {
      ...getCommonFetchParams(page),
      search: value,
      append,
    });
    searchPageNumber.value = page;
  },
  DEBOUNCE_DELAY
);

const loadMoreSearchResults = async () => {
  if (!hasMore.value || isLoadingMore.value) return;

  isLoadingMore.value = true;
  const nextPage = searchPageNumber.value + 1;

  await store.dispatch('contacts/search', {
    ...getCommonFetchParams(nextPage),
    search: searchValue.value,
    append: true,
  });

  searchPageNumber.value = nextPage;
  isLoadingMore.value = false;
};

const fetchContactsBasedOnContext = async (page, options = {}) => {
  const { clearSelection: shouldClearSelection = true } = options;
  if (shouldClearSelection) {
    clearSelection();
  }
  updatePageParam(page, searchValue.value);
  if (isFetchingList.value) return;
  if (searchQuery.value) {
    await searchContacts(searchQuery.value, page, false, {
      clearSelection: shouldClearSelection,
    });
    return;
  }
  // Reset the search value when we change the view
  searchValue.value = '';
  // If we're on the active route, fetch active contacts
  if (isActiveView.value) {
    await fetchActiveContacts(page, {
      clearSelection: shouldClearSelection,
    });
    return;
  }
  // If there are applied filters or active segment with query
  if (
    (hasAppliedFilters.value || activeSegment.value?.query) &&
    !activeLabel.value
  ) {
    const queryPayload =
      activeSegment.value?.query || filterQueryGenerator(appliedFilters.value);
    await fetchSavedOrAppliedFilteredContact(queryPayload, page, {
      clearSelection: shouldClearSelection,
    });
    return;
  }
  // Default case: fetch regular contacts + label
  await fetchContacts(page, {
    clearSelection: shouldClearSelection,
  });
};

const onPageChange = page =>
  fetchContactsBasedOnContext(page, { clearSelection: false });

// What the server needs to resolve this view for itself, branch for branch the same way
// `fetchContactsBasedOnContext` above decides which list to fetch — so the rows a bulk action reaches are the
// rows the list is showing, and not a second opinion about them (docs/contacts/10-phase-d.md §D4).
const viewDescription = computed(() => {
  if (searchQuery.value) return { q: searchQuery.value };
  if (isActiveView.value) return { active: true };
  if (
    (hasAppliedFilters.value || activeSegment.value?.query) &&
    !activeLabel.value
  ) {
    const query =
      activeSegment.value?.query || filterQueryGenerator(appliedFilters.value);
    return { payload: query.payload ?? [] };
  }
  return { label: activeLabel.value || '' };
});

const bulkTarget = computed(() =>
  isWholeViewSelected.value
    ? { all_matching: viewDescription.value }
    : { ids: selectedContactIds.value }
);

const runBulkAction = async ({ payload, success, failure, onDone }) => {
  if (!selectedContactIds.value.length) {
    return;
  }

  isBulkActionLoading.value = true;
  // Listening before the request is sent: a small selection can finish before the response lands.
  const completed = waitForBulkActionCompletion();
  try {
    await BulkActionsAPI.create({
      type: 'Contact',
      ...bulkTarget.value,
      ...payload,
    });
    await completed;
    useAlert(success);
    // Cleared only now — until the server has acted, the selection is what the user can retry with.
    clearSelection();
    await fetchContactsBasedOnContext(pageNumber.value);
    onDone?.();
  } catch (error) {
    // The one refusal worth quoting: a view with more contacts than one action may touch.
    useAlert(error.response?.data?.message ?? failure);
  } finally {
    isBulkActionLoading.value = false;
  }
};

const assignLabels = async labels => {
  if (!labels.length) {
    return;
  }

  await runBulkAction({
    payload: { labels: { add: labels } },
    success: t('CONTACTS_BULK_ACTIONS.ASSIGN_LABELS_SUCCESS'),
    failure: t('CONTACTS_BULK_ACTIONS.ASSIGN_LABELS_FAILED'),
  });
};

const removeLabels = async labels => {
  if (!labels.length) {
    return;
  }

  await runBulkAction({
    payload: { labels: { remove: labels } },
    success: t('CONTACTS_BULK_ACTIONS.REMOVE_LABELS_SUCCESS'),
    failure: t('CONTACTS_BULK_ACTIONS.REMOVE_LABELS_FAILED'),
  });
};

const deleteContacts = () =>
  runBulkAction({
    payload: { action_name: 'delete' },
    success: t('CONTACTS_BULK_ACTIONS.DELETE_SUCCESS'),
    failure: t('CONTACTS_BULK_ACTIONS.DELETE_FAILED'),
    onDone: () => bulkDeleteDialogRef.value?.close?.(),
  });

const handleSort = async ({ sort, order }) => {
  Object.assign(sortState, { activeSort: sort, activeOrdering: order });

  await updateUISettings({
    contacts_sort_by: buildSortAttr(),
  });

  if (searchQuery.value) {
    await searchContacts(searchValue.value, pageNumber.value, false, {
      clearSelection: false,
    });
    return;
  }

  if (isActiveView.value) {
    await fetchActiveContacts();
    return;
  }

  await (activeSegmentId.value || hasAppliedFilters.value
    ? fetchSavedOrAppliedFilteredContact(
        activeSegmentId.value
          ? activeSegment.value?.query
          : filterQueryGenerator(appliedFilters.value)
      )
    : fetchContacts());
};

// A created contact is in the store's `records` but deliberately not in the rendered list: only the server
// knows whether it belongs in this view and where it sorts. /contacts itself returns only contacts that have
// an email, phone or identifier, a label page only those carrying the label, and a new contact has no
// last_activity_at so it sorts last. So the list is re-read rather than guessed at.
const onContactCreated = async () => {
  // A search view is paged by infinite scroll, and re-reading it would discard every page after the first.
  if (isSearchView.value) return;
  // A segment whose definition has not loaded would fall through to the unfiltered list.
  if (activeSegmentId.value && !activeSegment.value?.query) return;

  await fetchContactsBasedOnContext(pageNumber.value, {
    clearSelection: false,
  });
};

watch(hasSelection, value => {
  if (!value) {
    bulkDeleteDialogRef.value?.close?.();
  }
});

watch(
  () => uiSettings.value?.contacts_sort_by,
  newSortBy => {
    if (newSortBy) {
      const { sort, order } = parseSortSettings(newSortBy);
      sortState.activeSort = sort;
      sortState.activeOrdering = order;
    }
  },
  { immediate: true }
);

watch(
  [activeLabel, activeSegment, isActiveView],
  () => {
    fetchContactsBasedOnContext(pageNumber.value);
  },
  { deep: true }
);

watch(searchQuery, value => {
  if (isFetchingList.value) return;
  searchValue.value = value || '';
  // Reset the view if there is search query when we click on the sidebar group
  if (value === undefined) {
    if (
      isActiveView.value ||
      activeLabel.value ||
      activeSegment.value ||
      hasAppliedFilters.value
    )
      return;
    fetchContacts();
  }
});

onMounted(async () => {
  if (!activeSegmentId.value) {
    if (searchQuery.value) {
      await searchContacts(searchQuery.value, pageNumber.value, false, {
        clearSelection: false,
      });
      return;
    }
    if (isActiveView.value) {
      await fetchActiveContacts(pageNumber.value);
      return;
    }
    await fetchContacts(pageNumber.value);
  } else if (activeSegment.value && activeSegmentId.value) {
    await fetchSavedOrAppliedFilteredContact(
      activeSegment.value.query,
      pageNumber.value
    );
  }
});
</script>

<template>
  <div
    class="flex flex-col justify-between flex-1 h-full m-0 overflow-auto bg-n-surface-1"
  >
    <ContactsListLayout
      :search-value="searchValue"
      :header-title="headerTitle"
      :current-page="currentPage"
      :total-items="totalItems"
      :show-pagination-footer="!isFetchingList && hasContacts && !isSearchView"
      :active-sort="sortState.activeSort"
      :active-ordering="sortState.activeOrdering"
      :active-segment="activeSegment"
      :segments-id="activeSegmentId"
      :is-fetching-list="isFetchingList"
      :has-applied-filters="hasAppliedFilters"
      :use-infinite-scroll="isSearchView"
      :has-more="hasMore"
      :is-loading-more="isLoadingMore"
      @update:current-page="onPageChange"
      @search="
        value => searchContacts(value, 1, false, { clearSelection: false })
      "
      @update:sort="handleSort"
      @apply-filter="fetchSavedOrAppliedFilteredContact"
      @clear-filters="fetchContacts"
      @load-more="loadMoreSearchResults"
      @contact-created="onContactCreated"
    >
      <div
        v-if="isFetchingList && !(isSearchView && hasContacts)"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>

      <template v-else>
        <ContactsBulkActionBar
          v-if="hasSelection"
          :visible-contact-ids="visibleContactIds"
          :selected-contact-ids="selectedContactIds"
          :is-loading="isBulkActionLoading"
          :total-count="totalItems ?? 0"
          :is-whole-view-selected="isWholeViewSelected"
          @toggle-all="toggleSelectAll"
          @select-all-matching="selectAllMatching"
          @clear-selection="clearSelection"
          @assign-labels="assignLabels"
          @remove-labels="removeLabels"
          @delete-selected="openBulkDeleteDialog"
        />
        <ContactEmptyState
          v-if="showEmptyStateLayout"
          class="pt-14"
          :title="t('CONTACTS_LAYOUT.EMPTY_STATE.TITLE')"
          :subtitle="t('CONTACTS_LAYOUT.EMPTY_STATE.SUBTITLE')"
          :button-label="t('CONTACTS_LAYOUT.EMPTY_STATE.BUTTON_LABEL')"
          @created="onContactCreated"
        />

        <div
          v-else-if="showEmptyText"
          class="flex items-center justify-center py-10"
        >
          <span class="text-base text-n-slate-11">
            {{ emptyStateMessage }}
          </span>
        </div>

        <div v-else class="flex flex-col gap-4 pt-4 pb-6">
          <ContactsList
            :contacts="contacts"
            :selected-contact-ids="selectedContactIds"
            @toggle-contact="toggleContactSelection"
          />
          <Dialog
            v-if="selectedCount"
            ref="bulkDeleteDialogRef"
            type="alert"
            :title="bulkDeleteDialogTitle"
            :description="bulkDeleteDialogDescription"
            :confirm-button-label="bulkDeleteDialogConfirmLabel"
            :is-loading="isBulkActionLoading"
            @confirm="deleteContacts"
          />
        </div>
      </template>
    </ContactsListLayout>
  </div>
</template>
