import { ref, computed } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import automation from 'dashboard/i18n/locale/en/automation.json';
import recipes from 'dashboard/i18n/locale/en/recipes.json';
import Index from '../Index.vue';
import { AUTOMATION_RECIPES } from 'dashboard/recipes/automationRecipes';

const dispatch = vi.fn();
const addOpen = vi.fn();
const alerts = [];
const query = ref({});
const records = ref([]);

vi.mock('dashboard/composables', () => ({
  useAlert: message => alerts.push(message),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useStoreGetters: () => ({
    'automations/getAutomations': computed(() => records.value),
    'automations/getUIFlags': computed(() => ({ isFetching: false })),
    getCurrentAccountId: computed(() => 1),
    'accounts/isFeatureEnabledonAccount': computed(() => () => false),
  }),
  useMapGetter: () => computed(() => ({ isFetchingItem: false })),
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ name: 'automation_list', params: {}, query: query.value }),
}));

const exposing = (open, template = '<div />') => ({
  setup(_, { expose }) {
    expose({ open, close: vi.fn() });
  },
  template,
});

const RecipeDialogStub = {
  props: ['recipes', 'title', 'description', 'isCreating'],
  emits: ['create', 'scratch'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<div data-test-id="recipe-dialog-stub" />',
};

const mountIndex = async () => {
  const wrapper = mount(Index, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...automation, ...recipes } },
        }),
      ],
      stubs: {
        SettingsLayout: {
          template:
            '<div><slot name="header" /><slot name="body" /><slot /></div>',
        },
        BaseSettingsHeader: { template: '<div><slot name="actions" /></div>' },
        BaseTable: { template: '<div><slot name="row" :items="[]" /></div>' },
        AddAutomationRule: exposing(addOpen),
        EditAutomationRule: exposing(vi.fn()),
        RecipeDialog: RecipeDialogStub,
        TabBar: true,
        AutomationRuleRow: true,
        'woot-delete-modal': true,
        'woot-confirm-modal': true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('automation Index', () => {
  beforeEach(() => {
    alerts.length = 0;
    dispatch.mockReset();
    addOpen.mockReset();
    dispatch.mockResolvedValue(undefined);
    query.value = {};
    records.value = [];
  });

  it('offers recipes and a blank rule in the empty state', async () => {
    const wrapper = await mountIndex();

    expect(
      wrapper.find('[data-test-id="automation-empty-state"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-test-id="automation-empty-recipes"]').exists()
    ).toBe(true);
    expect(wrapper.text()).toContain('No automation rules found');
  });

  it('creates a rule from a recipe switched off, and names where it came from', async () => {
    dispatch.mockImplementation(async (action, payload) =>
      action === 'automations/create' ? { id: 42, ...payload } : undefined
    );
    const wrapper = await mountIndex();
    const dialog = wrapper.findComponent(RecipeDialogStub);
    const recipe = dialog
      .props('recipes')
      .find(item => item.id === 'active_order_routing');
    dialog.vm.$emit('create', recipe, { team: 3 });
    await flushPromises();

    const [, payload] = dispatch.mock.calls.find(
      ([action]) => action === 'automations/create'
    );
    expect(payload).toEqual({
      event_name: 'conversation_created',
      conditions: [
        {
          attribute_key: 'commerce_active_order',
          filter_operator: 'equal_to',
          values: ['true'],
          query_operator: null,
        },
      ],
      actions: [{ action_name: 'assign_team', action_params: [3] }],
      active: false,
      name: 'Customer with an open order',
      description: 'Created from the Customer with an open order recipe (v1).',
    });
    expect(alerts).toContain('Created. Review it before you turn it on.');
  });

  it('reports a refused rule and stays on the list', async () => {
    dispatch.mockImplementation(async action => {
      if (action === 'automations/create') throw new Error('refused');
      return undefined;
    });
    const wrapper = await mountIndex();
    const dialog = wrapper.findComponent(RecipeDialogStub);
    dialog.vm.$emit('create', AUTOMATION_RECIPES[0], {
      store: 4,
      team: 3,
      labels: [],
    });
    await flushPromises();

    expect(alerts).toContain(
      'Couldn’t create it. Check the values and try again.'
    );
  });

  it('offers every recipe the catalogue has', async () => {
    const wrapper = await mountIndex();

    expect(
      wrapper.findComponent(RecipeDialogStub).props('recipes')
    ).toHaveLength(AUTOMATION_RECIPES.length);
  });

  it('opens the rule panel on the audience the route names', async () => {
    query.value = { audience: '9' };
    await mountIndex();

    expect(addOpen).toHaveBeenCalledWith({ audienceId: 9 });
  });

  it('opens nothing when the route names no audience', async () => {
    await mountIndex();

    expect(addOpen).not.toHaveBeenCalled();
  });
});
