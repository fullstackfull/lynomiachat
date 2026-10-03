import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import flowBuilder from 'dashboard/i18n/locale/en/flowBuilder.json';
import recipes from 'dashboard/i18n/locale/en/recipes.json';
import FlowsAPI from 'dashboard/api/flows';
import Index from '../Index.vue';

const push = vi.fn();
const alerts = [];

vi.mock('dashboard/api/flows', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
    create: vi.fn(),
    saveDraft: vi.fn(),
    delete: vi.fn(),
  },
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables', () => ({
  useAlert: message => alerts.push(message),
}));

const DialogStub = {
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div><slot /></div>',
};

const RecipeDialogStub = {
  props: ['recipes', 'title', 'description', 'isCreating'],
  emits: ['create', 'scratch'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div data-test-id="recipe-dialog-stub" />',
};

const PUBLISHED_WITH_DRAFT = {
  id: 1,
  name: 'Tracking',
  description: 'Finds orders',
  inboxes: [{ id: 2, name: 'WhatsApp' }],
  published: { id: 10, version: 3 },
  draft: { id: 11, version: 4 },
  live_sessions: 0,
};
const PUBLISHED_ONLY = {
  ...PUBLISHED_WITH_DRAFT,
  id: 2,
  name: 'Routing',
  draft: null,
};
const NEVER_PUBLISHED = {
  id: 3,
  name: 'Draft only',
  description: '',
  inboxes: [],
  published: null,
  draft: { id: 12, version: 1 },
  live_sessions: 0,
};

const mountIndex = async flows => {
  FlowsAPI.get.mockResolvedValue({ data: { payload: flows } });
  const wrapper = mount(Index, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...flowBuilder, ...recipes } },
        }),
      ],
      stubs: {
        SettingsLayout: {
          template:
            '<div><slot name="header" /><slot name="body" /><slot /></div>',
        },
        BaseSettingsHeader: { template: '<div><slot name="actions" /></div>' },
        Dialog: DialogStub,
        RecipeDialog: RecipeDialogStub,
        Input: true,
        BaseTable: {
          template: '<div><slot name="row" :items="$attrs.items" /></div>',
        },
        BaseTableRow: { template: '<div><slot /></div>' },
        BaseTableCell: { template: '<div><slot /></div>' },
      },
      directives: { tooltip: {} },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('flows Index', () => {
  beforeEach(() => {
    alerts.length = 0;
    push.mockClear();
    Object.values(FlowsAPI).forEach(fn => fn.mockReset?.());
  });

  it('says a published flow has unpublished changes, and only then', async () => {
    const wrapper = await mountIndex([
      PUBLISHED_WITH_DRAFT,
      PUBLISHED_ONLY,
      NEVER_PUBLISHED,
    ]);
    const marks = wrapper.findAll('[data-test-id="flow-unpublished"]');

    expect(marks).toHaveLength(1);
    expect(marks[0].text()).toBe('Unpublished changes');
    expect(wrapper.text()).toContain('Published · version 3');
    expect(wrapper.text()).toContain('Not published');
  });

  it("duplicates a flow by reading its graph and saving it as the copy's draft", async () => {
    const graph = { nodes: [{ id: 'start' }], edges: [] };
    FlowsAPI.show.mockResolvedValue({ data: { graph } });
    FlowsAPI.create.mockResolvedValue({ data: { id: 99 } });
    FlowsAPI.saveDraft.mockResolvedValue({ data: {} });

    const wrapper = await mountIndex([PUBLISHED_WITH_DRAFT]);
    await wrapper.find('[data-test-id="flow-duplicate-1"]').trigger('click');
    // The dialog prefills the copy's name; confirming runs the duplicate.
    await wrapper.vm.create();
    await flushPromises();

    expect(FlowsAPI.show).toHaveBeenCalledWith(1);
    expect(FlowsAPI.create).toHaveBeenCalledWith({
      name: 'Tracking copy',
      description: 'Finds orders',
    });
    expect(FlowsAPI.saveDraft).toHaveBeenCalledWith(99, graph);
    expect(push).toHaveBeenCalledWith({
      name: 'settings_flows_builder',
      params: { flowId: 99 },
    });
  });

  it('creates nothing when the source graph cannot be read', async () => {
    FlowsAPI.show.mockRejectedValue(new Error('nope'));

    const wrapper = await mountIndex([PUBLISHED_WITH_DRAFT]);
    await wrapper.find('[data-test-id="flow-duplicate-1"]').trigger('click');
    await wrapper.vm.create();
    await flushPromises();

    expect(FlowsAPI.create).not.toHaveBeenCalled();
    expect(alerts).toContain('The flow could not be duplicated.');
  });

  it('offers templates and a blank flow in the empty state', async () => {
    const wrapper = await mountIndex([]);

    expect(wrapper.find('[data-test-id="flow-empty-state"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-test-id="flow-empty-templates"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('No flows yet');
  });

  it('creates a flow from a template as an unpublished draft and opens the builder', async () => {
    FlowsAPI.create.mockResolvedValue({ data: { id: 55 } });
    FlowsAPI.saveDraft.mockResolvedValue({ data: {} });

    const wrapper = await mountIndex([]);
    const dialog = wrapper.findComponent(RecipeDialogStub);
    const template = dialog
      .props('recipes')
      .find(item => item.id === 'whatsapp_welcome_menu');
    dialog.vm.$emit('create', template, { team: 3, language: 'en' });
    await flushPromises();

    expect(FlowsAPI.create).toHaveBeenCalledWith({
      name: 'Welcome and collect the request',
      description:
        'Created from the Welcome and collect the request template (v1).',
    });
    const [flowId, graph] = FlowsAPI.saveDraft.mock.calls[0];
    expect(flowId).toBe(55);
    expect(graph.nodes.map(node => node.type)).toEqual([
      'start',
      'question',
      'send_message',
      'handoff',
    ]);
    expect(push).toHaveBeenCalledWith({
      name: 'settings_flows_builder',
      params: { flowId: 55 },
    });
  });

  it('reports a failed template create and stays on the list', async () => {
    FlowsAPI.create.mockRejectedValue(new Error('nope'));

    const wrapper = await mountIndex([]);
    const dialog = wrapper.findComponent(RecipeDialogStub);
    dialog.vm.$emit('create', dialog.props('recipes')[0], { team: 3 });
    await flushPromises();

    expect(alerts).toContain(
      'Couldn’t create it. Check the values and try again.'
    );
    expect(push).not.toHaveBeenCalled();
  });
});
