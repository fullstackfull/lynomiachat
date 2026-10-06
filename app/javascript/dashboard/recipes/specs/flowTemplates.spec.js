// Every flow template, in every language, checked against the backend's own graph contract. The rules below are
// transcribed from `custom/app/services/flows/node_types.rb`, `graph_validator.rb`, `node_validator.rb` and
// `channel_capabilities.rb`: a template that fails here would be refused by the server at publish, so this is the
// check that matters.
import { FLOW_TEMPLATES } from '../flowTemplates';
import { INPUT_TYPES, REQUIREMENTS } from '../index';
import { LANGUAGES } from '../starterCopy';

// Flows::NodeTypes::TYPES
const TYPES = {
  start: { outputs: ['next'], data: ['keywords', 'conditions'] },
  send_message: { outputs: ['next'], data: ['text'] },
  send_template: {
    outputs: ['next', 'failed'],
    optional: ['failed'],
    data: ['name', 'language', 'params'],
  },
  question: {
    outputs: ['reply', 'invalid', 'timeout'],
    optional: ['invalid', 'timeout'],
    wait: true,
    data: [
      'text',
      'reply_type',
      'keywords',
      'store_as',
      'max_attempts',
      'retry_text',
      'timeout_minutes',
    ],
  },
  buttons: {
    outputs: 'options',
    extra: ['other', 'timeout'],
    optional: ['other', 'timeout'],
    wait: true,
    data: ['text', 'options', 'timeout_minutes'],
  },
  list: {
    outputs: 'options',
    extra: ['other', 'timeout'],
    optional: ['other', 'timeout'],
    wait: true,
    data: ['text', 'button_label', 'options', 'timeout_minutes'],
  },
  condition: { outputs: ['true', 'false'], data: ['conditions'] },
  audience_condition: { outputs: ['true', 'false'], data: ['conditions'] },
  commerce_condition: { outputs: ['true', 'false'], data: ['conditions'] },
  set_contact_attribute: { outputs: ['next'], data: ['key', 'value'] },
  set_conversation_attribute: { outputs: ['next'], data: ['key', 'value'] },
  add_label: { outputs: ['next'], data: ['labels'] },
  remove_label: { outputs: ['next'], data: ['labels'] },
  assign_agent: {
    outputs: ['next', 'failed'],
    optional: ['failed'],
    data: ['agent_id'],
  },
  assign_team: {
    outputs: ['next', 'failed'],
    optional: ['failed'],
    data: ['team_id'],
  },
  commerce_lookup: {
    outputs: ['found', 'not_found', 'unavailable'],
    optional: ['not_found', 'unavailable'],
    data: ['mode', 'number'],
  },
  webhook: { outputs: ['next'], data: ['url'] },
  delay: { outputs: ['next'], wait: true, data: ['seconds'] },
  handoff: {
    outputs: [],
    data: ['team_id', 'agent_id', 'priority', 'labels', 'reason'],
  },
  goto: { outputs: [], data: ['target'] },
  end: { outputs: [], data: ['resolve'] },
};

// Flows::ChannelCapabilities::WHATSAPP
const CAPS = {
  text: { body: 4096 },
  buttons: { max: 3, title: 20, body: 1024 },
  list: { max: 10, title: 24, description: 72, body: 1024, button: 20 },
};
// Flows::GraphValidator
const MAX_NODES = 300;
const MAX_EDGES = 900;
const MAX_BYTES = 512 * 1024;
const ID = /^[A-Za-z0-9_-]{1,64}$/;
// Flows::NodeValidator
const REPLY_TYPES = ['any', 'number', 'email', 'phone', 'keywords'];
const LOOKUP_MODES = ['latest_order', 'order_number'];
const PRIORITIES = ['low', 'medium', 'high', 'urgent'];
const MAX_TIMEOUT_MINUTES = 1440;
const MAX_CONDITIONS = 10;
// Flows::Variables
const CONTEXT_KEY = /^[a-z][a-z0-9_]{0,39}$/;
const RESERVED = ['reply', 'order'];
const ORDER_FIELDS = [
  'number',
  'status',
  'payment_status',
  'tracking_number',
  'tracking_url',
];
const CHATWOOT_VARIABLE =
  /^(contact\.(name|first_name|last_name|email|phone_number|custom_attribute\.[A-Za-z0-9_-]+)|conversation\.(display_id|custom_attribute\.[A-Za-z0-9_-]+)|inbox\.name|account\.name)$/;

const outputsOf = node => {
  const spec = TYPES[node.type];
  if (spec.outputs !== 'options') return spec.outputs;
  return [
    ...(node.data.options || []).map(item => item.id),
    ...(spec.extra || []),
  ];
};

const requiredOutputsOf = node =>
  outputsOf(node).filter(
    output => !(TYPES[node.type].optional || []).includes(output)
  );

const waits = type => TYPES[type].wait === true;

const knownVariable = (name, flowOnly = false) => {
  if (!flowOnly && CHATWOOT_VARIABLE.test(name)) return true;
  if (!name.startsWith('flow.')) return false;

  const key = name.slice(5);
  return (
    key === 'reply' ||
    ORDER_FIELDS.map(field => `order.${field}`).includes(key) ||
    (CONTEXT_KEY.test(key) && !RESERVED.includes(key))
  );
};

const unknownVariables = (text, flowOnly = false) => {
  const found = [...String(text).matchAll(/\{\{\s*(.*?)\s*\}\}/g)].map(
    match => match[1]
  );
  return [
    ...(String(text).includes('{%') ? ['{%'] : []),
    ...found.filter(name => !knownVariable(name, flowOnly)),
  ];
};

// Context keys a Question in this graph stores, which later nodes may use as flow.<key>.
const storedKeys = nodes =>
  nodes
    .filter(node => node.type === 'question')
    .map(node => node.data.store_as)
    .filter(store => store?.scope === 'context')
    .map(store => store.key);

const reachable = graph => {
  const byId = Object.fromEntries(graph.nodes.map(node => [node.id, node]));
  const start = graph.nodes.find(node => node.type === 'start');
  const seen = new Set([start.id]);
  const queue = [start];
  while (queue.length) {
    const node = queue.shift();
    const targets = graph.edges
      .filter(item => item.source === node.id)
      .map(item => item.target);
    if (node.type === 'goto') targets.push(node.data.target);
    targets.forEach(id => {
      if (byId[id] && !seen.has(id)) {
        seen.add(id);
        queue.push(byId[id]);
      }
    });
  }
  return seen;
};

// Flows::GraphValidator#check_loops: a cycle among nodes that never wait is refused.
const hasLoopWithoutWait = graph => {
  const byId = Object.fromEntries(graph.nodes.map(node => [node.id, node]));
  const state = {};
  const successors = node => {
    const targets = graph.edges
      .filter(edge => edge.source === node.id)
      .map(edge => edge.target);
    if (node.type === 'goto') targets.push(node.data.target);
    return targets.map(id => byId[id]).filter(Boolean);
  };
  const cycleFrom = node => {
    state[node.id] = 'visiting';
    const found =
      !waits(node.type) &&
      successors(node).some(next => {
        if (waits(next.type)) return false;
        return (
          state[next.id] === 'visiting' ||
          (state[next.id] === undefined && cycleFrom(next))
        );
      });
    state[node.id] = 'done';
    return found;
  };
  return graph.nodes.some(
    node => state[node.id] === undefined && cycleFrom(node)
  );
};

const VALUES = {
  team: 3,
  orders_team: 3,
  products_team: 4,
  other_team: 5,
  vip_team: 3,
  standard_team: 4,
  arabic_team: 3,
  english_team: 4,
  audience: 9,
  labels: ['order-issue'],
  language: 'both',
};

const valuesFor = (templateItem, language) => ({
  ...VALUES,
  language,
});

describe('FLOW_TEMPLATES', () => {
  it('declares a complete manifest for every template', () => {
    FLOW_TEMPLATES.forEach(item => {
      expect(item.type).toBe('flow');
      expect(item.id).toMatch(/^[a-z][a-z0-9_]*$/);
      expect(item.version).toBe(1);
      expect(item.name).toBe(`RECIPES.FLOW.${item.id.toUpperCase()}.NAME`);
      expect(item.description).toBe(
        `RECIPES.FLOW.${item.id.toUpperCase()}.DESCRIPTION`
      );
      expect(item.requires).toContain(REQUIREMENTS.FLOW_BUILDER);
      expect(Object.values(INPUT_TYPES)).toEqual(
        expect.arrayContaining(item.inputs.map(input => input.type))
      );
    });
  });

  it('uses unique ids', () => {
    const ids = FLOW_TEMPLATES.map(item => item.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('asks for a Commerce feature only when it uses a Commerce node', () => {
    FLOW_TEMPLATES.forEach(item => {
      const graph = item.build(valuesFor(item, 'both'));
      const usesCommerce = graph.nodes.some(node =>
        ['commerce_lookup', 'commerce_condition'].includes(node.type)
      );
      expect(item.requires.includes(REQUIREMENTS.COMMERCE)).toBe(usesCommerce);
    });
  });

  it('asks for a shared audience only when it uses an audience condition', () => {
    FLOW_TEMPLATES.forEach(item => {
      const graph = item.build(valuesFor(item, 'both'));
      const usesAudience = graph.nodes.some(
        node => node.type === 'audience_condition'
      );
      expect(item.requires.includes(REQUIREMENTS.SHARED_AUDIENCE)).toBe(
        usesAudience
      );
    });
  });

  it('quotes the node and edge counts its graph really has', () => {
    FLOW_TEMPLATES.forEach(item => {
      const graph = item.build(valuesFor(item, 'both'));
      expect([item.id, item.nodeCount]).toEqual([item.id, graph.nodes.length]);
      expect([item.id, item.edgeCount]).toEqual([item.id, graph.edges.length]);
    });
  });

  LANGUAGES.forEach(language => {
    describe(`in ${language}`, () => {
      const graphs = () =>
        FLOW_TEMPLATES.map(item => [
          item,
          item.build(valuesFor(item, language)),
        ]);

      it('keeps the shape the graph validator accepts', () => {
        graphs().forEach(([item, graph]) => {
          expect(Array.isArray(graph.nodes), item.id).toBe(true);
          expect(Array.isArray(graph.edges), item.id).toBe(true);
          expect(graph.nodes.length).toBeLessThanOrEqual(MAX_NODES);
          expect(graph.edges.length).toBeLessThanOrEqual(MAX_EDGES);
          expect(
            new TextEncoder().encode(JSON.stringify(graph)).length
          ).toBeLessThan(MAX_BYTES);

          graph.nodes.forEach(node => {
            expect(Object.keys(node).sort(), `${item.id}/${node.id}`).toEqual([
              'data',
              'id',
              'position',
              'type',
            ]);
            expect(node.id).toMatch(ID);
            expect(TYPES[node.type], `${item.id}: ${node.type}`).toBeDefined();
            expect(Number.isFinite(node.position.x)).toBe(true);
            expect(Number.isFinite(node.position.y)).toBe(true);
            // Only the data keys this node type declares.
            expect(
              Object.keys(node.data).filter(
                key => !TYPES[node.type].data.includes(key)
              ),
              `${item.id}/${node.id}`
            ).toEqual([]);
          });
          graph.edges.forEach(edge => {
            expect(Object.keys(edge).sort()).toEqual([
              'id',
              'source',
              'sourceHandle',
              'target',
            ]);
            expect(edge.id).toMatch(ID);
          });

          const nodeIds = graph.nodes.map(node => node.id);
          expect(new Set(nodeIds).size, item.id).toBe(nodeIds.length);
          const edgeIds = graph.edges.map(edge => edge.id);
          expect(new Set(edgeIds).size, item.id).toBe(edgeIds.length);
        });
      });

      it('has exactly one Start, and nothing leading into it', () => {
        graphs().forEach(([item, graph]) => {
          expect(
            graph.nodes.filter(node => node.type === 'start').length,
            item.id
          ).toBe(1);
          const start = graph.nodes.find(node => node.type === 'start');
          expect(
            graph.edges.filter(edge => edge.target === start.id),
            item.id
          ).toEqual([]);
        });
      });

      it('connects every edge to an output that exists, once', () => {
        graphs().forEach(([item, graph]) => {
          const byId = Object.fromEntries(
            graph.nodes.map(node => [node.id, node])
          );
          const seen = new Set();
          graph.edges.forEach(edge => {
            const source = byId[edge.source];
            expect(source, `${item.id}: ${edge.source}`).toBeDefined();
            expect(
              byId[edge.target],
              `${item.id}: ${edge.target}`
            ).toBeDefined();
            expect(outputsOf(source), `${item.id}/${edge.id}`).toContain(
              edge.sourceHandle
            );
            const key = `${edge.source}:${edge.sourceHandle}`;
            expect(seen.has(key), `${item.id}/${key}`).toBe(false);
            seen.add(key);
          });
        });
      });

      it('connects every output the contract requires', () => {
        graphs().forEach(([item, graph]) => {
          const connected = new Set(
            graph.edges.map(edge => `${edge.source}:${edge.sourceHandle}`)
          );
          graph.nodes.forEach(node =>
            requiredOutputsOf(node).forEach(output =>
              expect(
                connected.has(`${node.id}:${output}`),
                `${item.id}/${node.id}/${output}`
              ).toBe(true)
            )
          );
        });
      });

      it('leaves no node unreachable from Start', () => {
        graphs().forEach(([item, graph]) => {
          const seen = reachable(graph);
          expect(
            graph.nodes.map(node => node.id).filter(id => !seen.has(id)),
            item.id
          ).toEqual([]);
        });
      });

      it('has no cycle that runs without waiting', () => {
        graphs().forEach(([item, graph]) =>
          expect(hasLoopWithoutWait(graph), item.id).toBe(false)
        );
      });

      it('stays inside what WhatsApp accepts for text, buttons and lists', () => {
        graphs().forEach(([item, graph]) => {
          graph.nodes.forEach(node => {
            const where = `${item.id}/${node.id}`;
            if (node.type === 'send_message') {
              expect(node.data.text.trim().length, where).toBeGreaterThan(0);
              expect(node.data.text.length, where).toBeLessThanOrEqual(
                CAPS.text.body
              );
            }
            if (node.type === 'question') {
              expect(node.data.text.trim().length, where).toBeGreaterThan(0);
              expect(node.data.text.length, where).toBeLessThanOrEqual(
                CAPS.text.body
              );
            }
            if (['buttons', 'list'].includes(node.type)) {
              const limits = CAPS[node.type];
              expect(node.data.text.trim().length, where).toBeGreaterThan(0);
              expect(node.data.text.length, where).toBeLessThanOrEqual(
                limits.body
              );
              expect(node.data.options.length, where).toBeGreaterThan(0);
              expect(node.data.options.length, where).toBeLessThanOrEqual(
                limits.max
              );
              const ids = node.data.options.map(choice => choice.id);
              expect(new Set(ids).size, where).toBe(ids.length);
              node.data.options.forEach(choice => {
                expect(choice.id).toMatch(ID);
                const length = choice.title.trim().length;
                expect(length, `${where}/${choice.id}`).toBeGreaterThan(0);
                expect(
                  length,
                  `${where}/${choice.id}: "${choice.title}"`
                ).toBeLessThanOrEqual(limits.title);
              });
            }
          });
        });
      });

      it('uses only variables the allow-list knows', () => {
        graphs().forEach(([item, graph]) => {
          const keys = storedKeys(graph.nodes);
          graph.nodes.forEach(node => {
            const where = `${item.id}/${node.id}`;
            ['text', 'retry_text'].forEach(field => {
              if (node.data[field]) {
                expect(unknownVariables(node.data[field]), where).toEqual([]);
              }
            });
            if (node.data.number) {
              // A lookup's order number is filled by the flow itself, so only flow.* is allowed there.
              expect(unknownVariables(node.data.number, true), where).toEqual(
                []
              );
              const used = [
                ...node.data.number.matchAll(/\{\{\s*flow\.(.*?)\s*\}\}/g),
              ].map(match => match[1]);
              used.forEach(key => {
                if (key !== 'reply' && !key.startsWith('order.')) {
                  expect(keys, where).toContain(key);
                }
              });
            }
          });
        });
      });

      it('fills each node data the way its own validator demands', () => {
        graphs().forEach(([item, graph]) => {
          graph.nodes.forEach(node => {
            const where = `${item.id}/${node.id}`;
            if (node.type === 'question') {
              expect(REPLY_TYPES, where).toContain(
                node.data.reply_type || 'any'
              );
              if (node.data.store_as?.scope === 'context') {
                expect(node.data.store_as.key, where).toMatch(CONTEXT_KEY);
                expect(RESERVED, where).not.toContain(node.data.store_as.key);
              }
            }
            if (['question', 'buttons', 'list'].includes(node.type)) {
              const timeout = node.data.timeout_minutes;
              if (timeout !== undefined) {
                expect(timeout, where).toBeGreaterThanOrEqual(1);
                expect(timeout, where).toBeLessThanOrEqual(MAX_TIMEOUT_MINUTES);
              }
            }
            if (node.type === 'commerce_lookup') {
              expect(LOOKUP_MODES, where).toContain(node.data.mode);
              if (node.data.number) {
                expect(node.data.mode, where).toBe('order_number');
                expect(node.data.number.length, where).toBeLessThanOrEqual(64);
              }
            }
            if (node.type === 'assign_team') {
              expect(node.data.team_id, where).toBeTruthy();
            }
            if (node.type === 'handoff') {
              if (node.data.priority) {
                expect(PRIORITIES, where).toContain(node.data.priority);
              }
              expect(
                String(node.data.reason || '').length,
                where
              ).toBeLessThanOrEqual(255);
              if (node.data.labels) {
                expect(node.data.labels.length, where).toBeLessThanOrEqual(10);
                node.data.labels.forEach(label =>
                  expect(typeof label, where).toBe('string')
                );
              }
            }
            if (
              [
                'condition',
                'audience_condition',
                'commerce_condition',
              ].includes(node.type)
            ) {
              expect(node.data.conditions.length, where).toBeGreaterThan(0);
              expect(node.data.conditions.length, where).toBeLessThanOrEqual(
                MAX_CONDITIONS
              );
              // At most one condition may carry a null query operator.
              expect(
                node.data.conditions.filter(
                  condition => condition.query_operator === null
                ).length,
                where
              ).toBeLessThanOrEqual(1);
            }
            if (node.type === 'audience_condition') {
              node.data.conditions.forEach(condition =>
                expect(condition.attribute_key, where).toBe('contact_audience')
              );
            }
          });
        });
      });

      it("names only this account's own resources, and only ones the wizard asked for", () => {
        const chosen = new Set([
          ...Object.values(VALUES).flat(),
          ...Object.values(VALUES),
        ]);
        graphs().forEach(([item, graph]) => {
          graph.nodes.forEach(node => {
            const where = `${item.id}/${node.id}`;
            ['team_id', 'agent_id'].forEach(field => {
              if (node.data[field] !== undefined) {
                expect(chosen.has(node.data[field]), where).toBe(true);
              }
            });
            (node.data.labels || []).forEach(label =>
              expect(VALUES.labels, where).toContain(label)
            );
            (node.data.conditions || []).forEach(condition =>
              condition.values.forEach(value =>
                expect(chosen.has(value), where).toBe(true)
              )
            );
          });
        });
      });
    });
  });

  it('builds a graph with no labels when none were chosen', () => {
    const afterSales = FLOW_TEMPLATES.find(
      item => item.id === 'commerce_after_sales'
    );
    const graph = afterSales.build({ team: 3, language: 'en' });

    graph.nodes
      .filter(node => node.type === 'handoff')
      .forEach(node => expect(node.data.labels).toBeUndefined());
  });

  it('puts the chosen priority on every complaint handoff, so the choice is not collected and dropped', () => {
    const complaint = FLOW_TEMPLATES.find(
      item => item.id === 'complaint_intake'
    );
    const handoffs = complaint
      .build({
        team: 3,
        labels: ['complaint'],
        priority: 'urgent',
        language: 'en',
      })
      .nodes.filter(node => node.type === 'handoff');

    expect(handoffs).toHaveLength(3);
    handoffs.forEach(node => expect(node.data.priority).toBe('urgent'));
  });

  it('sends a second FAQ question back to the same menu instead of a second copy of it', () => {
    const faq = FLOW_TEMPLATES.find(item => item.id === 'faq_menu');
    const graph = faq.build({ team: 3, language: 'en' });
    const again = graph.edges.find(
      edge => edge.source === 'ask_more' && edge.sourceHandle === 'again'
    );

    expect(again.target).toBe('menu');
    // And the loop is only safe because both ends wait for the customer.
    ['menu', 'ask_more'].forEach(id =>
      expect(['list', 'buttons', 'question', 'delay'], id).toContain(
        graph.nodes.find(node => node.id === id).type
      )
    );
  });

  it('sends Arabic only, English only, or both, as chosen', () => {
    const routing = FLOW_TEMPLATES.find(
      item => item.id === 'support_department_routing'
    );
    const textOf = language =>
      routing
        .build({ ...VALUES, language })
        .nodes.find(node => node.id === 'menu').data.text;

    expect(textOf('ar')).toBe(
      'مرحبًا! 👋 اختر الموضوع وسنوصلك بالفريق المناسب.'
    );
    expect(textOf('en')).toBe(
      'Hello! 👋 Choose a topic and we will connect you to the right team.'
    );
    expect(textOf('both')).toContain('\n');
    expect(textOf('both')).toContain('Hello!');
    expect(textOf('both')).toContain('مرحبًا!');
  });
});
