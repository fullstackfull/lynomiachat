// The builder's view of a flow graph (docs/flow-builder/03-data-model-and-versioning.md). The backend owns the graph
// contract: node types, their outputs and data keys come from the API (`node_types`), and the server validates every
// save and publish. This file only converts between the stored graph and Vue Flow, and lays out the palette.

export const NODE_GROUPS = [
  {
    key: 'MESSAGES',
    types: ['send_message', 'send_template', 'question', 'buttons', 'list'],
  },
  { key: 'LOGIC', types: ['condition'] },
  {
    key: 'CUSTOMER',
    types: [
      'set_contact_attribute',
      'set_conversation_attribute',
      'add_label',
      'remove_label',
      'audience_condition',
    ],
  },
  { key: 'COMMERCE', types: ['commerce_lookup', 'commerce_condition'] },
  { key: 'TEAM', types: ['assign_team', 'assign_agent', 'handoff'] },
  { key: 'INTEGRATION', types: ['webhook'] },
  { key: 'FLOW', types: ['delay', 'goto', 'end'] },
];

export const NODE_ICONS = {
  start: 'i-lucide-play',
  send_message: 'i-lucide-message-square',
  send_template: 'i-lucide-file-text',
  question: 'i-lucide-message-circle-question',
  buttons: 'i-lucide-rectangle-ellipsis',
  list: 'i-lucide-list',
  condition: 'i-lucide-git-branch',
  audience_condition: 'i-lucide-users',
  commerce_condition: 'i-lucide-shopping-bag',
  set_contact_attribute: 'i-lucide-user-pen',
  set_conversation_attribute: 'i-lucide-file-pen',
  add_label: 'i-lucide-tag',
  remove_label: 'i-lucide-tag',
  assign_agent: 'i-lucide-user-check',
  assign_team: 'i-lucide-users-round',
  commerce_lookup: 'i-lucide-package-search',
  webhook: 'i-lucide-webhook',
  delay: 'i-lucide-timer',
  handoff: 'i-lucide-headset',
  goto: 'i-lucide-corner-down-right',
  end: 'i-lucide-square',
};

const randomId = prefix =>
  `${prefix}_${Math.random().toString(36).slice(2, 10)}`;

export function newOption() {
  return { id: randomId('opt'), title: '' };
}

// What a new node starts with; the rest is filled in its panel.
const DEFAULT_DATA = {
  send_message: () => ({ text: '' }),
  send_template: () => ({ name: '', language: '', params: {} }),
  question: () => ({ text: '', reply_type: 'any' }),
  buttons: () => ({ text: '', options: [newOption()] }),
  list: () => ({ text: '', options: [newOption()] }),
  condition: () => ({ conditions: [] }),
  audience_condition: () => ({ conditions: [] }),
  commerce_condition: () => ({ conditions: [] }),
  set_contact_attribute: () => ({ key: '', value: '' }),
  set_conversation_attribute: () => ({ key: '', value: '' }),
  add_label: () => ({ labels: [] }),
  remove_label: () => ({ labels: [] }),
  assign_agent: () => ({ agent_id: null }),
  assign_team: () => ({ team_id: null }),
  commerce_lookup: () => ({ mode: 'latest_order' }),
  webhook: () => ({ url: '' }),
  delay: () => ({ seconds: 60 }),
  handoff: () => ({}),
  goto: () => ({ target: '' }),
  end: () => ({}),
};

export const defaultData = type => (DEFAULT_DATA[type] || (() => ({})))();

// The outputs a node can be connected from, as the backend's node contract defines them: a button or list node has
// one per option, plus its extra ones.
export function nodeOutputs(nodeTypes, type, data = {}) {
  const contract = nodeTypes?.[type];
  if (!contract) return [];
  if (contract.outputs !== 'options') return contract.outputs;

  return [
    ...(data.options || []).map(option => option.id).filter(Boolean),
    ...(contract.extra || []),
  ];
}

export const isOptionalOutput = (nodeTypes, type, output) =>
  (nodeTypes?.[type]?.optional || []).includes(output);

// Stored graph → Vue Flow. Vue Flow renders every node with the builder's one node component (type `flow`); the flow
// node type lives in `data.type`.
export function toCanvas(graph) {
  const nodes = (graph?.nodes || []).map(node => ({
    id: node.id,
    type: 'flow',
    position: { x: node.position?.x || 0, y: node.position?.y || 0 },
    deletable: node.type !== 'start',
    data: { type: node.type, data: node.data || {} },
  }));
  const edges = (graph?.edges || []).map(edge => ({
    id: edge.id,
    source: edge.source,
    sourceHandle: edge.sourceHandle,
    target: edge.target,
  }));
  return { nodes, edges };
}

// Vue Flow → stored graph: whole-pixel positions, and only edges whose output still exists (an option removed from a
// button node takes its edge with it).
export function fromCanvas(nodes, edges, nodeTypes) {
  const outputs = Object.fromEntries(
    nodes.map(node => [
      node.id,
      nodeOutputs(nodeTypes, node.data.type, node.data.data),
    ])
  );
  return {
    nodes: nodes.map(node => ({
      id: node.id,
      type: node.data.type,
      position: {
        x: Math.round(node.position.x),
        y: Math.round(node.position.y),
      },
      data: node.data.data,
    })),
    edges: edges
      .filter(edge => (outputs[edge.source] || []).includes(edge.sourceHandle))
      .map(edge => ({
        id: edge.id,
        source: edge.source,
        sourceHandle: edge.sourceHandle,
        target: edge.target,
      })),
  };
}

// One edge per output: connecting an output again replaces its edge. Nothing leads into Start, and a node never leads
// to itself.
export function connect(edges, { source, sourceHandle, target }, startId) {
  if (!sourceHandle || target === startId || source === target) return edges;

  return [
    ...edges.filter(
      edge => !(edge.source === source && edge.sourceHandle === sourceHandle)
    ),
    {
      id: `${source}-${sourceHandle}`,
      source,
      sourceHandle,
      target,
    },
  ];
}

export function createNode(type, position) {
  return {
    id: randomId(type.replace(/_/g, '-')),
    type: 'flow',
    position,
    deletable: true,
    data: { type, data: defaultData(type) },
  };
}

// A copy next to the original, with its own id; its outputs start unconnected.
export function duplicateNode(node) {
  return {
    ...createNode(node.data.type, {
      x: node.position.x + 40,
      y: node.position.y + 40,
    }),
    data: {
      type: node.data.type,
      data: JSON.parse(JSON.stringify(node.data.data)),
    },
  };
}

// Values a Question stores in the run (store_as context) become `flow.<key>` variables for later nodes.
export function flowVariables(nodes, suggested = []) {
  const stored = nodes
    .filter(node => node.data.type === 'question')
    .map(node => node.data.data.store_as)
    .filter(store => store?.scope === 'context' && store.key)
    .map(store => `flow.${store.key}`);
  return [...new Set([...suggested, ...stored])];
}

// A session's end reason or failure code as the builder shows it; "unrouted_<output>" names the output.
export const reasonLabel = (t, code) =>
  code.startsWith('unrouted_')
    ? t('FLOW_BUILDER.REASONS.UNROUTED', { output: code.slice(9) })
    : t(`FLOW_BUILDER.REASONS.${code.toUpperCase()}`);

// A server validation error as the builder shows it: the node's type, and an output named by its option title or label
// rather than its id.
export function errorLabel(t, error, nodes) {
  const node = nodes.find(item => item.id === error.node_id);
  let detail = error.detail ?? '';
  if (node && ['unconnected_output', 'duplicate_output'].includes(error.code)) {
    const option = (node.data.data.options || []).find(
      item => item.id === error.detail
    );
    detail = option
      ? option.title || error.detail
      : t(`FLOW_BUILDER.OUTPUTS.${String(error.detail).toUpperCase()}`);
  }
  const message = t(`FLOW_BUILDER.ERRORS.${error.code.toUpperCase()}`, {
    detail,
  });
  return node
    ? `${t(`FLOW_BUILDER.NODES.${node.data.type.toUpperCase()}`)}: ${message}`
    : message;
}
