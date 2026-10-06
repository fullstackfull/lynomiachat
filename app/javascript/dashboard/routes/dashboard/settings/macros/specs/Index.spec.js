import { ref, computed } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import macros from 'dashboard/i18n/locale/en/macros.json';
import recipes from 'dashboard/i18n/locale/en/recipes.json';
import labelMgmt from 'dashboard/i18n/locale/en/labelsMgmt.json';
import Index from '../Index.vue';

const dispatch = vi.fn();
const push = vi.fn();
const alerts = [];
const records = ref([]);
const isAdmin = ref(true);

vi.mock('dashboard/composables', () => ({
  useAlert: message => alerts.push(message),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useStoreGetters: () => ({
    'macros/getMacros': computed(() => records.value),
    'macros/getUIFlags': computed(() => ({ isFetching: false })),
  }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin }),
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRouter: () => ({ push }),
}));

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
          messages: { en: { ...macros, ...recipes, ...labelMgmt } },
        }),
      ],
      stubs: {
        SettingsLayout: {
          props: ['noRecordsFound'],
          template:
            '<div><slot name="header" /><slot v-if="noRecordsFound" name="emptyState" /><slot v-else name="body" /><slot /></div>',
        },
        BaseSettingsHeader: { template: '<div><slot name="actions" /></div>' },
        BaseTable: { template: '<div><slot name="row" :items="[]" /></div>' },
        RecipeDialog: RecipeDialogStub,
        Icon: true,
        // The from-scratch control is a router-link wrapping a Button; the router is mocked, so it needs a stub
        // that still renders its content.
        'router-link': { template: '<a><slot /></a>' },
        MacrosTableRow: true,
        'woot-delete-modal': true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('macros Index', () => {
  beforeEach(() => {
    alerts.length = 0;
    dispatch.mockReset();
    dispatch.mockResolvedValue(undefined);
    push.mockReset();
    records.value = [];
    isAdmin.value = true;
  });

  it('offers the starter gallery and a blank macro in the empty state', async () => {
    const wrapper = await mountIndex();

    expect(wrapper.find('[data-test-id="macro-empty-starters"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('No macros found');
    expect(wrapper.text()).toContain('Add a new macro');
  });

  it('names the starter gallery the same way everywhere it can be reached', async () => {
    const wrapper = await mountIndex();
    const labels = wrapper
      .findAll('button')
      .map(button => button.text())
      .filter(text => text.includes('Start from a starter'));

    // The header button and the empty-state button, one label.
    expect(labels).toHaveLength(2);
  });

  it('creates a macro from a starter and opens the editor on it, because a starter is a starting point', async () => {
    dispatch.mockImplementation(async (action, payload) =>
      action === 'macros/create' ? { id: 42, ...payload } : undefined
    );
    const wrapper = await mountIndex();
    const dialog = wrapper.findComponent(RecipeDialogStub);
    const starter = dialog
      .props('recipes')
      .find(item => item.id === 'take_conversation');
    dialog.vm.$emit('create', starter, {});
    await flushPromises();

    const [action, payload] = dispatch.mock.calls[1];
    expect(action).toBe('macros/create');
    expect(payload.visibility).toBe('global');
    expect(payload.actions).toEqual([
      { action_name: 'assign_agent', action_params: ['self'] },
      { action_name: 'change_priority', action_params: ['medium'] },
    ]);
    expect(push).toHaveBeenCalledWith({
      name: 'macros_edit',
      params: { macroId: 42 },
    });
  });

  it('asks for a personal macro when the user is not an administrator, which is all the server would give', async () => {
    isAdmin.value = false;
    dispatch.mockImplementation(async (action, payload) =>
      action === 'macros/create' ? { id: 43, ...payload } : undefined
    );
    const wrapper = await mountIndex();
    const dialog = wrapper.findComponent(RecipeDialogStub);
    dialog.vm.$emit(
      'create',
      dialog.props('recipes').find(item => item.id === 'take_conversation'),
      {}
    );
    await flushPromises();

    expect(dispatch.mock.calls[1][1].visibility).toBe('personal');
  });

  it('says so when the macro cannot be created, and stays where it is', async () => {
    dispatch.mockImplementation(async action => {
      if (action === 'macros/create') throw new Error('nope');
      return undefined;
    });
    const wrapper = await mountIndex();
    const dialog = wrapper.findComponent(RecipeDialogStub);
    dialog.vm.$emit(
      'create',
      dialog.props('recipes').find(item => item.id === 'take_conversation'),
      {}
    );
    await flushPromises();

    expect(alerts).toContain(
      'Couldn’t create it. Check the values and try again.'
    );
    expect(push).not.toHaveBeenCalled();
  });

  it('still lets someone start from nothing, in the editor they already knew', async () => {
    const wrapper = await mountIndex();
    wrapper.findComponent(RecipeDialogStub).vm.$emit('scratch');
    await flushPromises();

    expect(push).toHaveBeenCalledWith({ name: 'macros_new' });
  });
});
