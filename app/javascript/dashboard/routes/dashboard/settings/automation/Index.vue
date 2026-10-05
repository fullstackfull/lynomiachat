<script setup>
import { useAlert } from 'dashboard/composables';
import AddAutomationRule from './AddAutomationRule.vue';
import EditAutomationRule from './EditAutomationRule.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { until } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import {
  useMapGetter,
  useStoreGetters,
  useStore,
} from 'dashboard/composables/store';
import { picoSearch } from '@chatwoot/pico-search';
import AutomationRuleRow from './AutomationRuleRow.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { BaseTable } from 'dashboard/components-next/table';
import RecipeDialog from 'dashboard/components-next/recipes/RecipeDialog.vue';
import EmptyState from 'dashboard/components-next/empty-state/EmptyState.vue';
import { audienceIdFromQuery } from 'dashboard/helper/audienceHelper';
import { AUTOMATION_RECIPES } from 'dashboard/recipes/automationRecipes';
import { DEFAULT_DELAY_MINUTES } from './constants';

const getters = useStoreGetters();
const store = useStore();
const route = useRoute();
const { t } = useI18n();
const confirmDialog = ref(null);

const loading = ref({});
const addDialogRef = ref(null);
const editDialogRef = ref(null);
const recipeDialogRef = ref(null);
const isCreatingFromRecipe = ref(false);
const showDeleteConfirmationPopup = ref(false);
const selectedAutomation = ref({});
const searchQuery = ref('');
const toggleModalTitle = ref(t('AUTOMATION.TOGGLE.ACTIVATION_TITLE'));
const toggleModalDescription = ref(
  t('AUTOMATION.TOGGLE.ACTIVATION_DESCRIPTION')
);

const records = computed(() => getters['automations/getAutomations'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, ['name', 'description']);
});

const uiFlags = computed(() => getters['automations/getUIFlags'].value);
const accountId = computed(() => getters.getCurrentAccountId.value);
const accountUiFlags = useMapGetter('accounts/getUIFlags');

const isDelayedAutomationsEnabled = computed(() =>
  getters['accounts/isFeatureEnabledonAccount'].value(
    accountId.value,
    'delayed_automations'
  )
);

const instantRecords = computed(() =>
  filteredRecords.value.filter(automation => !automation.execution_delay)
);
const delayedRecords = computed(() =>
  filteredRecords.value.filter(automation => automation.execution_delay)
);

// Accounts that can't create delayed rules, and have none left over, just see the plain list.
const showTabs = computed(
  () =>
    isDelayedAutomationsEnabled.value ||
    records.value.some(automation => automation.execution_delay)
);

const activeTab = ref('instant');

const tabs = computed(() => [
  {
    key: 'instant',
    label: t('AUTOMATION.LIST.TABS.INSTANT'),
    count: instantRecords.value.length,
  },
  {
    key: 'delayed',
    label: t('AUTOMATION.LIST.TABS.DELAYED'),
    count: delayedRecords.value.length,
  },
]);

const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.key === activeTab.value)
);

const visibleRecords = computed(() => {
  if (!showTabs.value) return filteredRecords.value;
  return activeTab.value === 'delayed'
    ? delayedRecords.value
    : instantRecords.value;
});

const noDataMessage = computed(() => {
  if (searchQuery.value) return t('AUTOMATION.NO_RESULTS');
  return showTabs.value && activeTab.value === 'delayed'
    ? t('AUTOMATION.LIST.404_DELAYED')
    : t('AUTOMATION.LIST.404');
});

const onTabChanged = tab => {
  activeTab.value = tab.key;
};

const deleteConfirmText = computed(
  () => `${t('AUTOMATION.DELETE.CONFIRM.YES')} ${selectedAutomation.value.name}`
);

const deleteRejectText = computed(
  () => `${t('AUTOMATION.DELETE.CONFIRM.NO')} ${selectedAutomation.value.name}`
);

const deleteMessage = computed(() => ` ${selectedAutomation.value.name}?`);

const isSLAEnabled = computed(() =>
  getters['accounts/isFeatureEnabledonAccount'].value(accountId.value, 'sla')
);

let slaFetchPromise;

// Account feature flags may load after this page mounts, so watch the SLA flag
// to ensure its options are fetched after a hard refresh.
watch(
  isSLAEnabled,
  isEnabled => {
    if (isEnabled) {
      slaFetchPromise = store.dispatch('sla/get');
    }
  },
  { immediate: true }
);

const showDelayDisabledBanner = computed(
  () =>
    !isDelayedAutomationsEnabled.value &&
    records.value.some(automation => automation.execution_delay)
);

// "Use in a new automation rule", from an audience: the route says which one, and the panel opens on it. The query
// stays in the URL, so the link is shareable and a reload opens the same panel again. On mount is enough here:
// SettingsWrapper keys this page by the route's full path, so arriving with a different audience remounts it.
const openFromAudience = () => {
  const audienceId = audienceIdFromQuery(route.query);
  if (audienceId) addDialogRef.value?.open({ audienceId });
};

onMounted(() => {
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');
  store.dispatch('contacts/get');
  store.dispatch('teams/get');
  store.dispatch('labels/get');
  store.dispatch('campaigns/get');
  store.dispatch('automations/get');
  openFromAudience();
});

const openAddPopup = () => {
  const startsWithWait =
    isDelayedAutomationsEnabled.value && activeTab.value === 'delayed';
  addDialogRef.value?.open({
    executionDelay: startsWithWait ? DEFAULT_DELAY_MINUTES : null,
  });
};

const hideAddPopup = () => {
  addDialogRef.value?.close();
};

const openEditPopup = async response => {
  selectedAutomation.value = { ...response };
  await until(() => accountUiFlags.value.isFetchingItem).toBe(false);
  if (isSLAEnabled.value) {
    slaFetchPromise ||= store.dispatch('sla/get');
    await slaFetchPromise;
  }
  editDialogRef.value?.open(response);
};
const hideEditPopup = () => {
  editDialogRef.value?.close();
};

const openRecipes = () => recipeDialogRef.value?.open();

const startFromScratch = () => {
  recipeDialogRef.value?.close();
  openAddPopup();
};

// A recipe creates a real rule through the ordinary call, so the ordinary validation runs — including the checks that
// an audience is a shared one of this account and a store is this account's. It is created disabled and opened for
// review; turning it on stays the existing toggle, with its existing confirmation.
const createFromRecipe = async (automationRecipe, values) => {
  isCreatingFromRecipe.value = true;
  try {
    const created = await store.dispatch('automations/create', {
      ...automationRecipe.build(values),
      name: t(automationRecipe.name),
      description: t('RECIPES.AUTOMATION.PROVENANCE', {
        name: t(automationRecipe.name),
        version: automationRecipe.version,
      }),
    });
    recipeDialogRef.value?.close();
    useAlert(t('RECIPES.CREATED'));
    if (created) openEditPopup(created);
  } catch {
    useAlert(t('RECIPES.CREATE_ERROR'));
  } finally {
    isCreatingFromRecipe.value = false;
  }
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  selectedAutomation.value = response;
};
const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const deleteAutomation = async id => {
  try {
    await store.dispatch('automations/delete', id);
    useAlert(t('AUTOMATION.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AUTOMATION.DELETE.API.ERROR_MESSAGE'));
  } finally {
    loading.value[selectedAutomation.value.id] = false;
  }
};
const confirmDeletion = () => {
  loading.value[selectedAutomation.value.id] = true;
  closeDeletePopup();
  deleteAutomation(selectedAutomation.value.id);
};
const cloneAutomation = async ({ id }) => {
  try {
    await store.dispatch('automations/clone', id);
    useAlert(t('AUTOMATION.CLONE.API.SUCCESS_MESSAGE'));
    store.dispatch('automations/get');
  } catch (error) {
    useAlert(t('AUTOMATION.CLONE.API.ERROR_MESSAGE'));
  } finally {
    loading.value[selectedAutomation.value.id] = false;
  }
};

const submitAutomation = async (payload, mode) => {
  try {
    const action =
      mode === 'edit' ? 'automations/update' : 'automations/create';
    const successMessage =
      mode === 'edit'
        ? t('AUTOMATION.EDIT.API.SUCCESS_MESSAGE')
        : t('AUTOMATION.ADD.API.SUCCESS_MESSAGE');
    await store.dispatch(action, payload);
    useAlert(successMessage);
    hideAddPopup();
    hideEditPopup();
  } catch (error) {
    const fallbackMessage =
      mode === 'edit'
        ? t('AUTOMATION.EDIT.API.ERROR_MESSAGE')
        : t('AUTOMATION.ADD.API.ERROR_MESSAGE');
    useAlert(error?.response?.data?.error || fallbackMessage);
  }
};
const toggleAutomation = async ({ id, name, status }) => {
  try {
    if (status) {
      toggleModalTitle.value = t('AUTOMATION.TOGGLE.DEACTIVATION_TITLE');
      toggleModalDescription.value = t(
        'AUTOMATION.TOGGLE.DEACTIVATION_DESCRIPTION',
        {
          automationName: name,
        }
      );
    } else {
      toggleModalTitle.value = t('AUTOMATION.TOGGLE.ACTIVATION_TITLE');
      toggleModalDescription.value = t(
        'AUTOMATION.TOGGLE.ACTIVATION_DESCRIPTION',
        {
          automationName: name,
        }
      );
    }

    const ok = await confirmDialog.value.showConfirmation();
    if (ok) {
      await store.dispatch('automations/update', {
        id: id,
        active: !status,
      });
      const message = status
        ? t('AUTOMATION.TOGGLE.DEACTIVATION_SUCCESFUL')
        : t('AUTOMATION.TOGGLE.ACTIVATION_SUCCESFUL');
      useAlert(message);
    }
  } catch (error) {
    useAlert(t('AUTOMATION.EDIT.API.ERROR_MESSAGE'));
  }
};

// Index-aligned with `tableHeaders`.
const SORTABLE_COLUMNS = ['name', 'active', 'created_on', null];

// Four columns against a ~294px card at 390px: Active, Created on and the three row actions alone
// claim 280 of it, which is why the rule name renders as a single letter today. Created on moves into
// the name cell below `md` rather than disappearing.
const COLUMN_CLASSES = ['', '', 'hidden md:table-cell', ''];

const sortBy = ref('');
const sortOrder = ref('asc');

const onSort = ({ key, order }) => {
  sortBy.value = key;
  sortOrder.value = order;
};

const SORT_VALUES = {
  name: rule => rule.name ?? '',
  active: rule => (rule.active ? '1' : '0'),
  created_on: rule => String(rule.created_on ?? ''),
};

const sortedRecords = computed(() => {
  const read = SORT_VALUES[sortBy.value];
  if (!read) return visibleRecords.value;
  const direction = sortOrder.value === 'asc' ? 1 : -1;
  // Copy first: `getAutomations` hands back the store's own array, which it already sorts in place.
  return [...visibleRecords.value].sort(
    (a, b) => read(a).localeCompare(read(b)) * direction
  );
});

const tableHeaders = computed(() => {
  return [
    t('AUTOMATION.LIST.TABLE_HEADER.NAME'),
    t('AUTOMATION.LIST.TABLE_HEADER.ACTIVE'),
    t('AUTOMATION.LIST.TABLE_HEADER.CREATED_ON'),
    t('AUTOMATION.LIST.TABLE_HEADER.ACTIONS'),
  ];
});
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('AUTOMATION.HEADER')"
        :description="$t('AUTOMATION.DESCRIPTION')"
        :link-text="$t('AUTOMATION.LEARN_MORE')"
        :search-placeholder="$t('AUTOMATION.SEARCH_PLACEHOLDER')"
        feature-name="automation"
      >
        <template v-if="showTabs" #tabs>
          <TabBar
            :tabs="tabs"
            :initial-active-tab="activeTabIndex"
            @tab-changed="onTabChanged"
          />
        </template>
        <template v-if="visibleRecords.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('AUTOMATION.COUNT', { n: visibleRecords.length }) }}
          </span>
        </template>
        <template #actions>
          <div class="flex items-center gap-2">
            <Button
              :label="$t('RECIPES.AUTOMATION.ACTION')"
              size="sm"
              color="slate"
              variant="faded"
              data-test-id="automation-recipes-button"
              @click="openRecipes"
            />
            <Button
              :label="$t('AUTOMATION.HEADER_BTN_TXT')"
              size="sm"
              @click="openAddPopup"
            />
          </div>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <!-- The skeleton rows are aria-hidden, so this is what a screen reader hears during the fetch. -->
      <span v-if="uiFlags.isFetching" role="status" class="sr-only">
        {{ $t('AUTOMATION.LOADING') }}
      </span>
      <div
        v-if="showDelayDisabledBanner"
        class="px-4 py-3 mb-4 text-sm rounded-lg bg-n-amber-3 text-n-amber-12"
      >
        {{ $t('AUTOMATION.LIST.DELAY_DISABLED_BANNER') }}
      </div>
      <EmptyState
        v-if="!records.length && !uiFlags.isFetching"
        icon="i-lucide-repeat"
        :title="$t('AUTOMATION.LIST.404')"
        :description="$t('AUTOMATION.LIST.EMPTY_HINT')"
        data-test-id="automation-empty-state"
      >
        <template #action>
          <div class="flex flex-wrap items-center justify-center gap-2">
            <Button
              :label="$t('RECIPES.AUTOMATION.ACTION')"
              size="sm"
              icon="i-lucide-sparkles"
              data-test-id="automation-empty-recipes"
              @click="openRecipes"
            />
            <Button
              :label="$t('AUTOMATION.HEADER_BTN_TXT')"
              size="sm"
              color="slate"
              variant="faded"
              @click="openAddPopup"
            />
          </div>
        </template>
      </EmptyState>
      <BaseTable
        v-else
        sticky-header
        :headers="tableHeaders"
        align-last-column-end
        :items="sortedRecords"
        :loading="uiFlags.isFetching && !visibleRecords.length"
        :sortable-columns="SORTABLE_COLUMNS"
        :column-classes="COLUMN_CLASSES"
        :sort-by="sortBy"
        :sort-order="sortOrder"
        :no-data-message="noDataMessage"
        @sort="onSort"
      >
        <template #row="{ items }">
          <AutomationRuleRow
            v-for="automation in items"
            :key="automation.id"
            :automation="automation"
            :loading="loading[automation.id]"
            @clone="cloneAutomation"
            @toggle="toggleAutomation"
            @edit="openEditPopup"
            @delete="openDeletePopup"
          />
        </template>
      </BaseTable>
    </template>

    <AddAutomationRule ref="addDialogRef" @save-automation="submitAutomation" />

    <RecipeDialog
      ref="recipeDialogRef"
      :recipes="AUTOMATION_RECIPES"
      :title="$t('RECIPES.AUTOMATION.TITLE')"
      :description="$t('RECIPES.AUTOMATION.DESCRIPTION')"
      :is-creating="isCreatingFromRecipe"
      @create="createFromRecipe"
      @scratch="startFromScratch"
    />

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('LABEL_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('AUTOMATION.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
    />

    <EditAutomationRule
      ref="editDialogRef"
      :selected-response="selectedAutomation"
      @save-automation="submitAutomation"
    />
    <woot-confirm-modal
      ref="confirmDialog"
      :title="toggleModalTitle"
      :description="toggleModalDescription"
    />
  </SettingsLayout>
</template>
