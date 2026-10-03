<script setup>
import '@vue-flow/core/dist/style.css';
import { computed, onMounted, provide, ref } from 'vue';
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { VueFlow, Panel, useVueFlow } from '@vue-flow/core';
import { useEventListener } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import FlowsAPI from 'dashboard/api/flows';
import InboxesAPI from 'dashboard/api/inboxes';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import FlowNode from './components/FlowNode.vue';
import NodePalette from './components/NodePalette.vue';
import NodeConfigPanel from './components/NodeConfigPanel.vue';
import TestPanel from './components/TestPanel.vue';
import SessionsPanel from './components/SessionsPanel.vue';
import {
  connect,
  createNode,
  duplicateNode,
  errorLabel,
  flowVariables,
  fromCanvas,
  toCanvas,
} from './flowGraph';

// Lynomia Flow Builder (docs/flow-builder/02-architecture.md): edit a flow bot's draft on a canvas, check it with the
// server, test it on the real runtime, publish it, and see its sessions. The server owns the graph contract and is the
// only validation that counts; publishing turns the draft into the version new conversations start on.
const CANVAS_ID = 'lynomia-flow-builder';
const PANELS = { CONFIG: 'config', TEST: 'test', SESSIONS: 'sessions' };

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const { accountId, isCloudFeatureEnabled } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');
const { screenToFlowCoordinate, fitView, zoomIn, zoomOut, setCenter } =
  useVueFlow(CANVAS_ID);

const flowId = computed(() => Number(route.params.flowId));
const flow = ref(null);
const nodes = ref([]);
const edges = ref([]);
const errors = ref([]);
const capabilities = ref(null);
const nodeTypes = ref({});
const variables = ref([]);
const selectedId = ref(null);
const activeNodeId = ref(null);
const panel = ref(null);
const isLoading = ref(true);
const isSaving = ref(false);
const isPublishing = ref(false);
const savedGraph = ref('');
const inboxToConnect = ref('');
const disableDialogRef = ref(null);
const canvasRef = ref(null);
// The loaded graph is fitted once its nodes are measured (Vue Flow's pane can be ready before they are); adding a
// node later must not move the view.
const isFitted = ref(false);
const fitLoadedGraph = () => {
  if (isFitted.value) return;
  isFitted.value = true;
  fitView({ maxZoom: 1, padding: 0.3 });
};

// Unsaved: the graph differs from the one last loaded or saved (Vue Flow's own node state does not count).
const graphSnapshot = () =>
  JSON.stringify(fromCanvas(nodes.value, edges.value, nodeTypes.value));
const isDirty = computed(
  () => !isLoading.value && savedGraph.value !== graphSnapshot()
);

const commerceEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LYNOMIA_COMMERCE)
);
const startId = computed(
  () => nodes.value.find(node => node.data.type === 'start')?.id
);
const selectedNode = computed(() =>
  nodes.value.find(node => node.id === selectedId.value)
);
const errorNodeIds = computed(
  () => new Set(errors.value.map(error => error.node_id).filter(Boolean))
);
const flowErrors = computed(() => errors.value.filter(error => !error.node_id));
const selectedErrors = computed(() =>
  errors.value.filter(error => error.node_id === selectedId.value)
);
const allVariables = computed(() =>
  flowVariables(nodes.value, variables.value)
);
const whatsappInboxes = computed(() =>
  inboxes.value
    .filter(inbox => inbox.channel_type === 'Channel::Whatsapp')
    .filter(inbox => !flow.value?.inboxes.some(item => item.id === inbox.id))
    .map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const statusLabel = computed(() => {
  if (!flow.value) return '';
  const published = flow.value.published
    ? t('FLOW_BUILDER.STATUS.PUBLISHED', {
        version: flow.value.published.version,
      })
    : t('FLOW_BUILDER.STATUS.NOT_PUBLISHED');
  if (isDirty.value) {
    return `${published} · ${t('FLOW_BUILDER.STATUS.UNSAVED')}`;
  }
  // Saved, but publishing has not made it live: a flow keeps a draft only until it is published.
  return flow.value.published && flow.value.draft
    ? `${published} · ${t('FLOW_BUILDER.STATUS.UNPUBLISHED')}`
    : published;
});

provide('flowBuilder', { nodeTypes, errorNodeIds, activeNodeId });

const errorText = error => errorLabel(t, error, nodes.value);

const apply = data => {
  flow.value = data;
  errors.value = data.errors || [];
  if (data.capabilities) capabilities.value = data.capabilities;
  if (data.node_types) nodeTypes.value = data.node_types;
  if (data.variables) variables.value = data.variables;
};

const load = async () => {
  isLoading.value = true;
  isFitted.value = false;
  try {
    const { data } = await FlowsAPI.show(flowId.value);
    apply(data);
    const canvas = toCanvas(data.graph);
    nodes.value = canvas.nodes;
    edges.value = canvas.edges;
    savedGraph.value = graphSnapshot();
  } catch {
    // A flow of another account, a deleted one, or the feature switched off: back to the list.
    useAlert(t('FLOW_BUILDER.API.LOAD_ERROR'));
    router.replace({ name: 'settings_flows_index' });
  } finally {
    isLoading.value = false;
  }
};

const save = async () => {
  isSaving.value = true;
  try {
    const snapshot = graphSnapshot();
    const { data } = await FlowsAPI.saveDraft(
      flowId.value,
      JSON.parse(snapshot)
    );
    apply(data);
    savedGraph.value = snapshot;
    return true;
  } catch (error) {
    errors.value = error?.response?.data?.errors || [];
    useAlert(t('FLOW_BUILDER.API.SAVE_ERROR'));
    return false;
  } finally {
    isSaving.value = false;
  }
};

const saveIfDirty = async () => {
  if (isDirty.value && !(await save())) throw new Error('unsaved');
};

const publish = async () => {
  isPublishing.value = true;
  try {
    await saveIfDirty();
    const { data } = await FlowsAPI.publish(flowId.value);
    flow.value = { ...flow.value, ...data };
    errors.value = [];
    useAlert(
      t('FLOW_BUILDER.API.PUBLISHED', { version: data.published.version })
    );
  } catch (error) {
    const found = error?.response?.data?.errors;
    if (found) errors.value = found;
    useAlert(t('FLOW_BUILDER.API.PUBLISH_ERROR'));
  } finally {
    isPublishing.value = false;
  }
};

const disable = async () => {
  disableDialogRef.value.close();
  const { data } = await FlowsAPI.disable(flowId.value);
  flow.value = { ...flow.value, ...data };
  useAlert(t('FLOW_BUILDER.API.DISABLED'));
};

const connectInbox = async () => {
  if (!inboxToConnect.value) return;
  await InboxesAPI.setAgentBot(inboxToConnect.value, flowId.value);
  inboxToConnect.value = '';
  await load();
  useAlert(t('FLOW_BUILDER.API.INBOX_CONNECTED'));
};

const disconnectInbox = async inboxId => {
  await InboxesAPI.setAgentBot(inboxId, null);
  await load();
};

// A new node arrives selected, with its settings open.
const addNode = (type, position) => {
  const node = { ...createNode(type, position), selected: true };
  nodes.value = [
    ...nodes.value.map(item => ({ ...item, selected: false })),
    node,
  ];
  selectedId.value = node.id;
  panel.value = PANELS.CONFIG;
};

const addAtCenter = type => {
  const rect = canvasRef.value.getBoundingClientRect();
  addNode(
    type,
    screenToFlowCoordinate({
      x: rect.left + rect.width / 2,
      y: rect.top + rect.height / 3,
    })
  );
};

const onDrop = event => {
  const type = event.dataTransfer?.getData('application/lynomia-flow-node');
  if (!type) return;
  addNode(type, screenToFlowCoordinate({ x: event.clientX, y: event.clientY }));
};

const onConnect = connection => {
  edges.value = connect(edges.value, connection, startId.value);
};

const selectNode = id => {
  selectedId.value = id;
  panel.value = id ? PANELS.CONFIG : null;
};

const updateNodeData = data => {
  nodes.value = nodes.value.map(node =>
    node.id === selectedId.value
      ? { ...node, data: { ...node.data, data } }
      : node
  );
};

const deleteSelected = () => {
  const id = selectedId.value;
  nodes.value = nodes.value.filter(node => node.id !== id);
  edges.value = edges.value.filter(
    edge => edge.source !== id && edge.target !== id
  );
  selectNode(null);
};

const duplicateSelected = () => {
  const copy = { ...duplicateNode(selectedNode.value), selected: true };
  nodes.value = [
    ...nodes.value.map(item => ({ ...item, selected: false })),
    copy,
  ];
  selectNode(copy.id);
};

const focusNode = id => {
  activeNodeId.value = id;
  const node = nodes.value.find(item => item.id === id);
  if (node) setCenter(node.position.x + 120, node.position.y + 60, { zoom: 1 });
};

const openPanel = name => {
  panel.value = panel.value === name ? null : name;
  if (panel.value !== PANELS.CONFIG) selectedId.value = null;
  if (!panel.value) activeNodeId.value = null;
};

onBeforeRouteLeave(() =>
  // eslint-disable-next-line no-alert
  isDirty.value ? window.confirm(t('FLOW_BUILDER.UNSAVED_CONFIRM')) : true
);

// A reload or a closed tab leaves the router out of it, so the route guard above never runs: the browser's own prompt
// is the only thing that can still ask.
useEventListener(window, 'beforeunload', event => {
  if (!isDirty.value) return;
  event.preventDefault();
  event.returnValue = '';
});

// Cmd/Ctrl+S is what anyone editing a graph reaches for; unbound, it opens the browser's save-page dialog instead.
// Allowed while a config field has focus: that is exactly when the draft is worth keeping.
useKeyboardEvents({
  '$mod+KeyS': {
    action: event => {
      event.preventDefault();
      if (isDirty.value && !isSaving.value) save();
    },
    allowOnFocusedInput: true,
  },
});

// Labels, inboxes, teams and custom attributes are loaded by the dashboard's sidebar on every page; fetching the
// cached ones again at the same moment made two cache refreshes collide in IndexedDB.
onMounted(() => {
  store.dispatch('agents/get');
  load();
});
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-surface-1">
    <header
      class="flex flex-wrap items-center gap-3 px-4 py-3 border-b border-n-weak shrink-0"
    >
      <NextButton
        v-tooltip="t('FLOW_BUILDER.CANVAS.BACK')"
        :aria-label="t('FLOW_BUILDER.CANVAS.BACK')"
        icon="i-lucide-arrow-left"
        slate
        ghost
        sm
        class="rtl:rotate-180"
        @click="router.push({ name: 'settings_flows_index' })"
      />
      <div class="flex flex-col min-w-0">
        <h1 class="m-0 text-base font-medium text-n-slate-12 truncate">
          {{ flow?.name }}
        </h1>
        <span class="text-xs text-n-slate-11" data-test-id="flow-status">
          {{ statusLabel }}
        </span>
      </div>
      <div class="flex flex-wrap items-center gap-2 ms-auto">
        <span
          v-for="inbox in flow?.inboxes || []"
          :key="inbox.id"
          class="flex items-center gap-1 px-2 py-1 text-xs rounded-lg bg-n-alpha-2 text-n-slate-12"
        >
          {{ inbox.name }}
          <button
            type="button"
            class="i-lucide-x size-3 text-n-slate-11"
            :aria-label="t('FLOW_BUILDER.INBOXES.DISCONNECT')"
            @click="disconnectInbox(inbox.id)"
          />
        </span>
        <Select
          v-if="whatsappInboxes.length"
          v-model="inboxToConnect"
          :options="whatsappInboxes"
          :placeholder="t('FLOW_BUILDER.INBOXES.CONNECT')"
          @update:model-value="connectInbox"
        />
        <NextButton
          :label="t('FLOW_BUILDER.ACTIONS.SESSIONS')"
          icon="i-lucide-activity"
          slate
          faded
          sm
          @click="openPanel(PANELS.SESSIONS)"
        />
        <NextButton
          :label="t('FLOW_BUILDER.ACTIONS.TEST')"
          icon="i-lucide-flask-conical"
          slate
          faded
          sm
          data-test-id="flow-test-button"
          @click="openPanel(PANELS.TEST)"
        />
        <NextButton
          v-tooltip.bottom="t('FLOW_BUILDER.ACTIONS.SAVE_HINT')"
          :label="t('FLOW_BUILDER.ACTIONS.SAVE')"
          slate
          sm
          :is-loading="isSaving"
          :disabled="!isDirty"
          data-test-id="flow-save-button"
          @click="save"
        />
        <NextButton
          v-if="flow?.published"
          :label="t('FLOW_BUILDER.ACTIONS.DISABLE')"
          ruby
          faded
          sm
          @click="disableDialogRef.open()"
        />
        <NextButton
          :label="t('FLOW_BUILDER.ACTIONS.PUBLISH')"
          sm
          :is-loading="isPublishing"
          data-test-id="flow-publish-button"
          @click="publish"
        />
      </div>
    </header>

    <div v-if="isLoading" class="flex items-center justify-center flex-1">
      <Spinner />
    </div>
    <div v-else class="relative flex flex-1 min-h-0">
      <NodePalette :commerce-enabled="commerceEnabled" @add="addAtCenter" />
      <div
        ref="canvasRef"
        class="relative flex-1 min-w-0"
        dir="ltr"
        @dragover.prevent
        @drop="onDrop"
      >
        <VueFlow
          :id="CANVAS_ID"
          v-model:nodes="nodes"
          v-model:edges="edges"
          :min-zoom="0.2"
          :max-zoom="2"
          :delete-key-code="['Delete', 'Backspace']"
          class="bg-n-surface-2"
          @connect="onConnect"
          @node-click="selectNode($event.node.id)"
          @pane-click="selectNode(null)"
          @nodes-initialized="fitLoadedGraph"
        >
          <template #node-flow="nodeProps">
            <FlowNode v-bind="nodeProps" />
          </template>
          <Panel position="bottom-left" class="flex gap-1">
            <NextButton
              v-tooltip="t('FLOW_BUILDER.CANVAS.ZOOM_IN')"
              :aria-label="t('FLOW_BUILDER.CANVAS.ZOOM_IN')"
              icon="i-lucide-plus"
              slate
              faded
              xs
              @click="zoomIn()"
            />
            <NextButton
              v-tooltip="t('FLOW_BUILDER.CANVAS.ZOOM_OUT')"
              :aria-label="t('FLOW_BUILDER.CANVAS.ZOOM_OUT')"
              icon="i-lucide-minus"
              slate
              faded
              xs
              @click="zoomOut()"
            />
            <NextButton
              v-tooltip="t('FLOW_BUILDER.CANVAS.FIT_VIEW')"
              :aria-label="t('FLOW_BUILDER.CANVAS.FIT_VIEW')"
              icon="i-lucide-maximize"
              slate
              faded
              xs
              data-test-id="flow-fit-view"
              @click="fitView({ maxZoom: 1, padding: 0.2 })"
            />
          </Panel>
          <Panel
            v-if="flowErrors.length || errors.length"
            position="top-left"
            class="max-w-sm p-3 rounded-xl bg-n-solid-1 outline outline-1 outline-n-ruby-6"
            data-test-id="flow-errors"
          >
            <p class="m-0 mb-1 text-sm font-medium text-n-ruby-11">
              {{ t('FLOW_BUILDER.ERRORS_TITLE', { n: errors.length }) }}
            </p>
            <ul class="m-0 text-xs list-none text-n-slate-12" dir="auto">
              <li
                v-for="(error, index) in errors.slice(0, 8)"
                :key="index"
                :class="{ 'cursor-pointer hover:underline': error.node_id }"
                @click="
                  error.node_id &&
                    (selectNode(error.node_id), focusNode(error.node_id))
                "
              >
                {{ errorText(error) }}
              </li>
            </ul>
          </Panel>
        </VueFlow>
      </div>
      <NodeConfigPanel
        v-if="panel === PANELS.CONFIG && selectedNode && capabilities"
        :key="selectedNode.id"
        :node="selectedNode"
        :nodes="nodes"
        :capabilities="capabilities"
        :variables="allVariables"
        :inbox-ids="(flow?.inboxes || []).map(inbox => inbox.id)"
        :errors="selectedErrors.map(errorText)"
        @update="updateNodeData"
        @delete="deleteSelected"
        @duplicate="duplicateSelected"
        @close="selectNode(null)"
      />
      <TestPanel
        v-if="panel === PANELS.TEST"
        :flow-id="flowId"
        :before-run="saveIfDirty"
        @node="focusNode"
        @close="openPanel(PANELS.TEST)"
      />
      <SessionsPanel
        v-if="panel === PANELS.SESSIONS"
        :flow-id="flowId"
        :account-id="accountId"
        @node="focusNode"
        @close="openPanel(PANELS.SESSIONS)"
      />
    </div>

    <Dialog
      ref="disableDialogRef"
      type="alert"
      :title="t('FLOW_BUILDER.DISABLE.TITLE')"
      :description="t('FLOW_BUILDER.DISABLE.DESCRIPTION')"
      :confirm-button-label="t('FLOW_BUILDER.DISABLE.CONFIRM')"
      @confirm="disable"
    />
  </div>
</template>
