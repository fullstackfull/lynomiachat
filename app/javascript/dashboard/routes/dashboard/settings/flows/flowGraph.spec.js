import {
  connect,
  duplicateNode,
  flowVariables,
  fromCanvas,
  nodeOutputs,
  toCanvas,
} from './flowGraph';

const nodeTypes = {
  start: { outputs: ['next'] },
  buttons: {
    outputs: 'options',
    extra: ['other', 'timeout'],
    optional: ['other', 'timeout'],
  },
  send_message: { outputs: ['next'] },
  end: { outputs: [] },
};

const graph = {
  nodes: [
    { id: 'start', type: 'start', position: { x: 0, y: 0 }, data: {} },
    {
      id: 'menu',
      type: 'buttons',
      position: { x: 10.4, y: 120.6 },
      data: {
        text: 'Hi',
        options: [
          { id: 'track', title: 'Track' },
          { id: 'care', title: 'Care' },
        ],
      },
    },
    { id: 'end', type: 'end', position: { x: 0, y: 300 }, data: {} },
  ],
  edges: [
    { id: 'e1', source: 'start', sourceHandle: 'next', target: 'menu' },
    { id: 'e2', source: 'menu', sourceHandle: 'track', target: 'end' },
    { id: 'e3', source: 'menu', sourceHandle: 'care', target: 'end' },
  ],
};

describe('flowGraph', () => {
  it('gives a choice node one output per option plus its extra outputs', () => {
    expect(nodeOutputs(nodeTypes, 'buttons', graph.nodes[1].data)).toEqual([
      'track',
      'care',
      'other',
      'timeout',
    ]);
    expect(nodeOutputs(nodeTypes, 'end')).toEqual([]);
  });

  it('round-trips a graph through the canvas, rounding positions and keeping Start undeletable', () => {
    const { nodes, edges } = toCanvas(graph);
    expect(nodes[0]).toMatchObject({ type: 'flow', deletable: false });

    const saved = fromCanvas(nodes, edges, nodeTypes);
    expect(saved.nodes[1].position).toEqual({ x: 10, y: 121 });
    expect(saved.edges).toEqual(graph.edges);
  });

  it('drops the edge of an option that was removed', () => {
    const { nodes, edges } = toCanvas(graph);
    nodes[1].data.data.options = [{ id: 'track', title: 'Track' }];

    expect(fromCanvas(nodes, edges, nodeTypes).edges.map(e => e.id)).toEqual([
      'e1',
      'e2',
    ]);
  });

  it('keeps one edge per output and never leads into Start or a node itself', () => {
    const { edges } = toCanvas(graph);
    const replaced = connect(
      edges,
      { source: 'menu', sourceHandle: 'track', target: 'menu' },
      'start'
    );
    expect(replaced).toBe(edges);

    const moved = connect(
      edges,
      { source: 'start', sourceHandle: 'next', target: 'end' },
      'start'
    );
    expect(moved.filter(edge => edge.source === 'start')).toEqual([
      {
        id: 'start-next',
        source: 'start',
        sourceHandle: 'next',
        target: 'end',
      },
    ]);
    expect(
      connect(
        edges,
        { source: 'menu', sourceHandle: 'care', target: 'start' },
        'start'
      )
    ).toBe(edges);
  });

  it('duplicates a node with a new id and its own copy of the data', () => {
    const { nodes } = toCanvas(graph);
    const copy = duplicateNode(nodes[1]);
    copy.data.data.options[0].title = 'Changed';

    expect(copy.id).not.toBe('menu');
    expect(nodes[1].data.data.options[0].title).toBe('Track');
    expect(copy.position).toEqual({ x: 50.4, y: 160.6 });
  });

  it('offers the values Questions store as flow variables', () => {
    const { nodes } = toCanvas({
      nodes: [
        {
          id: 'q',
          type: 'question',
          position: { x: 0, y: 0 },
          data: { store_as: { scope: 'context', key: 'order_no' } },
        },
      ],
    });
    expect(flowVariables(nodes, ['flow.reply'])).toEqual([
      'flow.reply',
      'flow.order_no',
    ]);
  });
});
