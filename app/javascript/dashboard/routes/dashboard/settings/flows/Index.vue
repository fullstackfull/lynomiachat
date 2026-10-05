<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import FlowsAPI from 'dashboard/api/flows';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import WootLabel from 'dashboard/components-next/label/Label.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import RecipeDialog from 'dashboard/components-next/recipes/RecipeDialog.vue';
import EmptyState from 'dashboard/components-next/empty-state/EmptyState.vue';
import { FLOW_TEMPLATES } from 'dashboard/recipes/flowTemplates';

// The account's flows (Lynomia Flow Builder): each is a bot that answers its inboxes' conversations until it hands them
// to humans. Created here, edited in the builder, connected to inboxes there.
const router = useRouter();
const { t } = useI18n();

const flows = ref([]);
const isLoading = ref(true);
const createDialogRef = ref(null);
const deleteDialogRef = ref(null);
const templateDialogRef = ref(null);
const isCreatingFromTemplate = ref(false);
const name = ref('');
const description = ref('');
const selected = ref(null);
const isCreating = ref(false);
// The flow a new one is copied from, when the create dialog is being used to duplicate.
const copyFrom = ref(null);

const headers = computed(() => [
  t('FLOW_BUILDER.LIST.NAME'),
  t('FLOW_BUILDER.LIST.STATUS'),
  t('FLOW_BUILDER.LIST.INBOXES'),
  t('FLOW_BUILDER.LIST.ACTIONS'),
]);

// Index-aligned with `headers`.
const SORTABLE_COLUMNS = ['name', 'published', 'inboxes', null];

// Four columns do not fit a 390px card: the actions alone need 120px of it. Status and the inbox list
// move into the name cell below those breakpoints rather than disappearing — see the template.
const COLUMN_CLASSES = ['', 'hidden sm:table-cell', 'hidden md:table-cell', ''];

const sortBy = ref('');
const sortOrder = ref('asc');

const onSort = ({ key, order }) => {
  sortBy.value = key;
  sortOrder.value = order;
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await FlowsAPI.get();
    flows.value = data.payload;
  } catch {
    useAlert(t('FLOW_BUILDER.API.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const openBuilder = flow =>
  router.push({ name: 'settings_flows_builder', params: { flowId: flow.id } });

const openCreate = () => {
  copyFrom.value = null;
  name.value = '';
  description.value = '';
  createDialogRef.value.open();
};

// Duplicate: the copy is a new flow of this account with the source's graph as its draft. It starts unpublished and
// connected to no inbox — an inbox holds one bot, so connecting the copy would take the inbox away from the original.
const openDuplicate = flow => {
  copyFrom.value = flow;
  name.value = t('FLOW_BUILDER.DUPLICATE.NAME', { name: flow.name });
  description.value = flow.description || '';
  createDialogRef.value.open();
};

const create = async () => {
  isCreating.value = true;
  try {
    // The source graph is read first: a failure here creates nothing.
    const graph = copyFrom.value
      ? (await FlowsAPI.show(copyFrom.value.id)).data.graph
      : null;
    const { data } = await FlowsAPI.create({
      name: name.value.trim(),
      description: description.value.trim(),
    });
    if (graph) await FlowsAPI.saveDraft(data.id, graph);
    createDialogRef.value.close();
    openBuilder(data);
  } catch {
    useAlert(
      t(
        copyFrom.value
          ? 'FLOW_BUILDER.API.DUPLICATE_ERROR'
          : 'FLOW_BUILDER.API.CREATE_ERROR'
      )
    );
    if (copyFrom.value) load();
  } finally {
    isCreating.value = false;
  }
};

const openTemplates = () => templateDialogRef.value?.open();

// A template is a prepared draft: the flow is created with the ordinary call, its graph saved as the draft with the
// ordinary call, and the builder opens on it. It is unpublished and connected to no inbox, so nothing reaches a
// customer until the user publishes it themselves.
const createFromTemplate = async (flowTemplate, values) => {
  isCreatingFromTemplate.value = true;
  try {
    const { data } = await FlowsAPI.create({
      name: t(flowTemplate.name),
      description: t('RECIPES.FLOW.PROVENANCE', {
        name: t(flowTemplate.name),
        version: flowTemplate.version,
      }),
    });
    await FlowsAPI.saveDraft(data.id, flowTemplate.build(values));
    templateDialogRef.value?.close();
    openBuilder(data);
  } catch {
    useAlert(t('RECIPES.CREATE_ERROR'));
    load();
  } finally {
    isCreatingFromTemplate.value = false;
  }
};

const startFromScratch = () => {
  templateDialogRef.value?.close();
  openCreate();
};

const confirmDelete = flow => {
  selected.value = flow;
  deleteDialogRef.value.open();
};

const remove = async () => {
  deleteDialogRef.value.close();
  try {
    await FlowsAPI.delete(selected.value.id);
    useAlert(t('FLOW_BUILDER.API.DELETED'));
    load();
  } catch {
    useAlert(t('FLOW_BUILDER.API.DELETE_ERROR'));
  }
};

const status = flow =>
  flow.published
    ? t('FLOW_BUILDER.STATUS.PUBLISHED', { version: flow.published.version })
    : t('FLOW_BUILDER.STATUS.NOT_PUBLISHED');

// Publishing turns the draft into the published version, so a flow that has both has edits that are saved but not
// live yet. Not a guess: the API payload carries each version.
const hasUnpublishedChanges = flow => Boolean(flow.published && flow.draft);

// One source for the inbox list: the column, its narrow-width copy and the sort key cannot drift.
const inboxNames = flow =>
  flow.inboxes.map(inbox => inbox.name).join(', ') ||
  t('FLOW_BUILDER.LIST.NO_INBOX');

const SORT_VALUES = {
  name: flow => flow.name ?? '',
  published: flow =>
    flow.published
      ? `1${String(flow.published.version).padStart(6, '0')}`
      : '0',
  inboxes: flow => inboxNames(flow),
};

const sortedFlows = computed(() => {
  const read = SORT_VALUES[sortBy.value];
  if (!read) return flows.value;
  const direction = sortOrder.value === 'asc' ? 1 : -1;
  return [...flows.value].sort(
    (a, b) => read(a).localeCompare(read(b)) * direction
  );
});

onMounted(load);
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="t('FLOW_BUILDER.HEADER')"
        :description="t('FLOW_BUILDER.DESCRIPTION')"
      >
        <template #actions>
          <div class="flex items-center gap-2">
            <NextButton
              :label="t('RECIPES.FLOW.ACTION')"
              size="sm"
              color="slate"
              variant="faded"
              data-test-id="flow-templates-button"
              @click="openTemplates"
            />
            <NextButton
              :label="t('FLOW_BUILDER.LIST.NEW')"
              size="sm"
              data-test-id="flow-new-button"
              @click="openCreate"
            />
          </div>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <!-- The skeleton rows are aria-hidden, so this is what a screen reader hears during the fetch. -->
      <span v-if="isLoading" role="status" class="sr-only">
        {{ t('FLOW_BUILDER.LIST.LOADING') }}
      </span>
      <EmptyState
        v-if="!flows.length && !isLoading"
        icon="i-lucide-workflow"
        :title="t('FLOW_BUILDER.LIST.EMPTY')"
        :description="t('FLOW_BUILDER.LIST.EMPTY_HINT')"
        data-test-id="flow-empty-state"
      >
        <template #action>
          <div class="flex flex-wrap items-center justify-center gap-2">
            <NextButton
              :label="t('RECIPES.FLOW.ACTION')"
              size="sm"
              icon="i-lucide-sparkles"
              data-test-id="flow-empty-templates"
              @click="openTemplates"
            />
            <NextButton
              :label="t('FLOW_BUILDER.LIST.NEW')"
              size="sm"
              color="slate"
              variant="faded"
              @click="openCreate"
            />
          </div>
        </template>
      </EmptyState>
      <BaseTable
        v-else
        :headers="headers"
        align-last-column-end
        :items="sortedFlows"
        :loading="isLoading"
        :loading-rows="3"
        :sortable-columns="SORTABLE_COLUMNS"
        :column-classes="COLUMN_CLASSES"
        :sort-by="sortBy"
        :sort-order="sortOrder"
        @sort="onSort"
      >
        <template #row="{ items }">
          <BaseTableRow v-for="flow in items" :key="flow.id" :item="flow">
            <template #default>
              <BaseTableCell class="max-w-0 w-full">
                <button
                  type="button"
                  class="flex flex-col w-full min-w-0 text-start"
                  @click="openBuilder(flow)"
                >
                  <span class="text-body-main text-n-slate-12 truncate">
                    {{ flow.name }}
                  </span>
                  <span class="text-body-main text-n-slate-11 truncate">
                    {{ flow.description }}
                  </span>
                </button>
                <!-- What the hidden columns say, where they say it on a phone. Outside the button, so
                     the flow's accessible name is the same at every width. -->
                <div class="flex flex-wrap items-center gap-1 mt-1 sm:hidden">
                  <WootLabel
                    compact
                    variant="solid"
                    :label="status(flow)"
                    :tone="flow.published ? 'success' : 'neutral'"
                  />
                  <WootLabel
                    v-if="hasUnpublishedChanges(flow)"
                    compact
                    variant="solid"
                    tone="warning"
                    :label="t('FLOW_BUILDER.STATUS.UNPUBLISHED')"
                  />
                </div>
                <span
                  class="block md:hidden mt-1 text-label-small text-n-slate-11 truncate"
                >
                  {{ inboxNames(flow) }}
                </span>
              </BaseTableCell>
              <BaseTableCell class="hidden sm:table-cell">
                <div class="flex flex-col items-start gap-1">
                  <WootLabel
                    compact
                    variant="solid"
                    :label="status(flow)"
                    :tone="flow.published ? 'success' : 'neutral'"
                  />
                  <WootLabel
                    v-if="hasUnpublishedChanges(flow)"
                    compact
                    variant="solid"
                    tone="warning"
                    data-test-id="flow-unpublished"
                    :label="t('FLOW_BUILDER.STATUS.UNPUBLISHED')"
                  />
                  <span
                    v-if="flow.live_sessions"
                    class="text-label-small text-n-slate-11"
                  >
                    {{ t('FLOW_BUILDER.LIST.LIVE', { n: flow.live_sessions }) }}
                  </span>
                </div>
              </BaseTableCell>
              <BaseTableCell class="max-w-0 hidden md:table-cell">
                <span class="text-body-main text-n-slate-11 truncate block">
                  {{ inboxNames(flow) }}
                </span>
              </BaseTableCell>
              <BaseTableCell align="end" class="w-32">
                <div class="flex justify-end gap-3">
                  <NextButton
                    v-tooltip.top="t('FLOW_BUILDER.LIST.OPEN')"
                    :aria-label="t('FLOW_BUILDER.LIST.OPEN')"
                    icon="i-lucide-workflow"
                    slate
                    sm
                    @click="openBuilder(flow)"
                  />
                  <NextButton
                    v-tooltip.top="t('FLOW_BUILDER.LIST.DUPLICATE')"
                    :aria-label="t('FLOW_BUILDER.LIST.DUPLICATE')"
                    icon="i-lucide-copy"
                    slate
                    sm
                    :data-test-id="`flow-duplicate-${flow.id}`"
                    @click="openDuplicate(flow)"
                  />
                  <NextButton
                    v-tooltip.top="t('FLOW_BUILDER.LIST.DELETE')"
                    :aria-label="t('FLOW_BUILDER.LIST.DELETE')"
                    icon="i-woot-bin"
                    slate
                    sm
                    :disabled="Boolean(flow.published)"
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    @click="confirmDelete(flow)"
                  />
                </div>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <Dialog
      ref="createDialogRef"
      :title="
        copyFrom
          ? t('FLOW_BUILDER.DUPLICATE.TITLE')
          : t('FLOW_BUILDER.CREATE.TITLE')
      "
      :confirm-button-label="t('FLOW_BUILDER.CREATE.CONFIRM')"
      :disable-confirm-button="!name.trim()"
      :is-loading="isCreating"
      @confirm="create"
    >
      <div class="flex flex-col gap-3">
        <Input
          v-model="name"
          :label="t('FLOW_BUILDER.CREATE.NAME')"
          data-test-id="flow-name-input"
        />
        <Input
          v-model="description"
          :label="t('FLOW_BUILDER.CREATE.DESCRIPTION')"
        />
      </div>
    </Dialog>
    <RecipeDialog
      ref="templateDialogRef"
      :recipes="FLOW_TEMPLATES"
      :title="t('RECIPES.FLOW.TITLE')"
      :description="t('RECIPES.FLOW.DESCRIPTION')"
      :is-creating="isCreatingFromTemplate"
      @create="createFromTemplate"
      @scratch="startFromScratch"
    />
    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('FLOW_BUILDER.DELETE.TITLE', { name: selected?.name })"
      :description="t('FLOW_BUILDER.DELETE.DESCRIPTION')"
      :confirm-button-label="t('FLOW_BUILDER.DELETE.CONFIRM')"
      @confirm="remove"
    />
  </SettingsLayout>
</template>
