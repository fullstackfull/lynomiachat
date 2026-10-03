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
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

// The account's flows (Lynomia Flow Builder): each is a bot that answers its inboxes' conversations until it hands them
// to humans. Created here, edited in the builder, connected to inboxes there.
const router = useRouter();
const { t } = useI18n();

const flows = ref([]);
const isLoading = ref(true);
const createDialogRef = ref(null);
const deleteDialogRef = ref(null);
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

onMounted(load);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="t('FLOW_BUILDER.LIST.LOADING')"
    :no-records-found="!flows.length"
    :no-records-message="t('FLOW_BUILDER.LIST.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('FLOW_BUILDER.HEADER')"
        :description="t('FLOW_BUILDER.DESCRIPTION')"
      >
        <template #actions>
          <NextButton
            :label="t('FLOW_BUILDER.LIST.NEW')"
            size="sm"
            data-test-id="flow-new-button"
            @click="openCreate"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable :headers="headers" :items="flows">
        <template #row="{ items }">
          <BaseTableRow v-for="flow in items" :key="flow.id" :item="flow">
            <template #default>
              <BaseTableCell class="max-w-0">
                <button
                  type="button"
                  class="flex flex-col min-w-0 text-start"
                  @click="openBuilder(flow)"
                >
                  <span class="text-body-main text-n-slate-12 truncate">
                    {{ flow.name }}
                  </span>
                  <span class="text-body-main text-n-slate-11 truncate">
                    {{ flow.description }}
                  </span>
                </button>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12">
                  {{ status(flow) }}
                </span>
                <span
                  v-if="hasUnpublishedChanges(flow)"
                  class="block text-xs text-n-amber-11"
                  data-test-id="flow-unpublished"
                >
                  {{ t('FLOW_BUILDER.STATUS.UNPUBLISHED') }}
                </span>
                <span
                  v-if="flow.live_sessions"
                  class="block text-xs text-n-slate-11"
                >
                  {{ t('FLOW_BUILDER.LIST.LIVE', { n: flow.live_sessions }) }}
                </span>
              </BaseTableCell>
              <BaseTableCell class="max-w-0">
                <span class="text-body-main text-n-slate-11 truncate block">
                  {{
                    flow.inboxes.map(inbox => inbox.name).join(', ') ||
                    t('FLOW_BUILDER.LIST.NO_INBOX')
                  }}
                </span>
              </BaseTableCell>
              <BaseTableCell align="end" class="w-24">
                <div class="flex justify-end gap-3">
                  <NextButton
                    v-tooltip.top="t('FLOW_BUILDER.LIST.OPEN')"
                    icon="i-lucide-workflow"
                    slate
                    sm
                    @click="openBuilder(flow)"
                  />
                  <NextButton
                    v-tooltip.top="t('FLOW_BUILDER.LIST.DUPLICATE')"
                    icon="i-lucide-copy"
                    slate
                    sm
                    :data-test-id="`flow-duplicate-${flow.id}`"
                    @click="openDuplicate(flow)"
                  />
                  <NextButton
                    v-tooltip.top="t('FLOW_BUILDER.LIST.DELETE')"
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
