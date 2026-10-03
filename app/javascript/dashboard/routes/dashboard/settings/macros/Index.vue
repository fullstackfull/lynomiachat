<script setup>
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@chatwoot/pico-search';
import MacrosTableRow from './MacrosTableRow.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import { BaseTable } from 'dashboard/components-next/table';
import { useAdmin } from 'dashboard/composables/useAdmin';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

const showDeleteConfirmationPopup = ref(false);
const selectedMacro = ref({});
const searchQuery = ref('');
// Empty until a heading is clicked, so the default order is the store's own.
const sortBy = ref('');
const sortOrder = ref('asc');

const records = computed(() => getters['macros/getMacros'].value);
const uiFlags = computed(() => getters['macros/getUIFlags'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, ['name']);
});

// The same resolution the row renders, so the arrow and the column never disagree.
const personName = person => person?.available_name ?? person?.email ?? '';

const SORT_VALUES = {
  name: macro => macro.name ?? '',
  created_by: macro => personName(macro.created_by),
  updated_by: macro => personName(macro.updated_by),
  visibility: macro => macro.visibility ?? '',
};

const sortedRecords = computed(() => {
  const read = SORT_VALUES[sortBy.value];
  if (!read) return filteredRecords.value;
  const direction = sortOrder.value === 'asc' ? 1 : -1;
  // Copy first: with an empty search box `filteredRecords` is the store's own array by reference.
  return [...filteredRecords.value].sort(
    (a, b) => read(a).localeCompare(read(b)) * direction
  );
});

const handleSort = ({ key, order }) => {
  sortBy.value = key;
  sortOrder.value = order;
};

const deleteMessage = computed(() => ` ${selectedMacro.value.name}?`);

onMounted(() => {
  store.dispatch('macros/get');
});

const deleteMacro = async id => {
  try {
    await store.dispatch('macros/delete', id);
    useAlert(t('MACROS.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('MACROS.DELETE.API.ERROR_MESSAGE'));
  }
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  selectedMacro.value = response;
};

const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const confirmDeletion = () => {
  closeDeletePopup();
  deleteMacro(selectedMacro.value.id);
};

// Index-aligned with `tableHeaders`.
const SORTABLE_COLUMNS = [
  'name',
  'created_by',
  'updated_by',
  'visibility',
  null,
];

// Five columns do not fit a phone. Who made it and who last touched it are the two a user scanning
// their macro library can do without there; both stay in full from `sm` up, and neither is the only
// place that information lives — the macro editor shows both.
const COLUMN_CLASSES = [
  null,
  'hidden sm:table-cell',
  'hidden sm:table-cell',
  null,
  null,
];

const tableHeaders = computed(() => {
  return [
    t('MACROS.LIST.TABLE_HEADER.NAME'),
    t('MACROS.LIST.TABLE_HEADER.CREATED BY'),
    t('MACROS.LIST.TABLE_HEADER.LAST_UPDATED_BY'),
    t('MACROS.LIST.TABLE_HEADER.VISIBILITY'),
    t('MACROS.LIST.TABLE_HEADER.ACTIONS'),
  ];
});
</script>

<template>
  <SettingsLayout
    :no-records-message="$t('MACROS.LIST.404')"
    :no-records-found="!uiFlags.isFetching && !records.length"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('MACROS.HEADER')"
        :description="$t('MACROS.DESCRIPTION')"
        :link-text="$t('MACROS.LEARN_MORE')"
        :search-placeholder="$t('MACROS.SEARCH_PLACEHOLDER')"
        feature-name="macros"
      >
        <template v-if="records?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('MACROS.COUNT', { n: records.length }) }}
          </span>
        </template>
        <template #actions>
          <router-link :to="{ name: 'macros_new' }">
            <Button :label="$t('MACROS.HEADER_BTN_TXT')" size="sm" />
          </router-link>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable
        sticky-header
        :headers="tableHeaders"
        align-last-column-end
        :items="sortedRecords"
        :loading="uiFlags.isFetching"
        :loading-message="$t('MACROS.LOADING')"
        :sortable-columns="SORTABLE_COLUMNS"
        :column-classes="COLUMN_CLASSES"
        :sort-by="sortBy"
        :sort-order="sortOrder"
        :no-data-message="
          searchQuery ? $t('MACROS.NO_RESULTS') : $t('MACROS.LIST.404')
        "
        @sort="handleSort"
      >
        <template #row="{ items }">
          <MacrosTableRow
            v-for="macro in items"
            :key="macro.id"
            :macro="macro"
            :can-manage-public-macros="isAdmin"
            @delete="openDeletePopup(macro)"
          />
        </template>
      </BaseTable>
      <woot-delete-modal
        v-model:show="showDeleteConfirmationPopup"
        :on-close="closeDeletePopup"
        :on-confirm="confirmDeletion"
        :title="$t('LABEL_MGMT.DELETE.CONFIRM.TITLE')"
        :message="$t('MACROS.DELETE.CONFIRM.MESSAGE')"
        :message-value="deleteMessage"
        :confirm-text="$t('MACROS.DELETE.CONFIRM.YES')"
        :reject-text="$t('MACROS.DELETE.CONFIRM.NO')"
      />
    </template>
  </SettingsLayout>
</template>
