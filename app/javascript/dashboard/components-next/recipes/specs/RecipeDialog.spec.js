import { ref, computed } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import recipes from 'dashboard/i18n/locale/en/recipes.json';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import automation from 'dashboard/i18n/locale/en/automation.json';
import RecipeDialog from '../RecipeDialog.vue';
import { CATEGORIES, INPUT_TYPES, REQUIREMENTS } from 'dashboard/recipes';

const enabledFlags = ref(['crm', 'lynomia_commerce', 'automations']);
const stores = ref([
  { id: 4, name: 'Syria Cosmetics', provider: 'woocommerce' },
]);
const currencies = ref(['SAR', 'AED']);
const teams = ref([
  { id: 1, name: 'Support' },
  { id: 2, name: 'Sales' },
]);

const GETTERS = {
  'teams/getTeams': () => teams.value,
  'labels/getLabels': () => [{ id: 1, title: 'vip' }],
};

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name => computed(() => (GETTERS[name] || (() => []))()),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => enabledFlags.value.includes(flag),
  }),
}));
vi.mock('dashboard/components-next/filter/audienceProvider', () => ({
  useAudienceFilterTypes: () => ({
    loadAudienceFields: vi.fn().mockResolvedValue(undefined),
    commerceStores: computed(() => stores.value),
    commerceCurrencies: computed(() => currencies.value),
  }),
}));

const DialogStub = {
  props: ['title', 'description', 'isLoading'],
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template:
    '<div><p data-test-id="dialog-title">{{ title }}</p><slot /><slot name="footer" /></div>',
};

const recipe = (id, { requires = [], inputs = [] } = {}) => ({
  id,
  type: 'audience',
  version: 1,
  name: 'RECIPES.AUDIENCE.REPEAT_BUYERS.NAME',
  description: 'RECIPES.AUDIENCE.REPEAT_BUYERS.DESCRIPTION',
  category: CATEGORIES.ECOMMERCE,
  requires,
  inputs,
  build: values => ({ values }),
});

const mountDialog = async (list, isCreating = false) => {
  const wrapper = mount(RecipeDialog, {
    props: {
      recipes: list,
      title: 'Start from a preset',
      description: 'Pick one',
      isCreating,
    },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...recipes, ...conversation, ...automation } },
        }),
      ],
      stubs: { Dialog: DialogStub, Icon: true },
    },
  });
  await wrapper.vm.open();
  await flushPromises();
  return wrapper;
};

describe('RecipeDialog', () => {
  beforeEach(() => {
    enabledFlags.value = ['crm', 'lynomia_commerce', 'automations'];
    stores.value = [
      { id: 4, name: 'Syria Cosmetics', provider: 'woocommerce' },
    ];
    currencies.value = ['SAR', 'AED'];
    teams.value = [
      { id: 1, name: 'Support' },
      { id: 2, name: 'Sales' },
    ];
  });

  it('says why a recipe is near the top, rather than leaving the order a mystery', async () => {
    const commerce = recipe('commerce', { requires: [REQUIREMENTS.COMMERCE] });
    const plain = recipe('plain');
    const wrapper = await mountDialog([plain, commerce]);

    const marker = wrapper.find('[data-test-id="recipe-commerce-recommended"]');
    expect(marker.exists()).toBe(true);
    expect(marker.text()).toBe('Fits your store');
    expect(
      wrapper.find('[data-test-id="recipe-plain-recommended"]').exists()
    ).toBe(false);
  });

  it('recommends nothing on a store’s account that has no store connected', async () => {
    stores.value = [];
    const wrapper = await mountDialog([
      recipe('commerce', { requires: [REQUIREMENTS.COMMERCE] }),
    ]);

    expect(
      wrapper.find('[data-test-id="recipe-commerce-recommended"]').exists()
    ).toBe(false);
  });

  it('tells someone what their store platform cannot do, both in the list and after they pick it', async () => {
    const withNote = {
      ...recipe('tracking'),
      providerNote: 'RECIPES.FLOW.COMMERCE_ORDER_TRACKING.PROVIDER_NOTE',
    };
    const wrapper = await mountDialog([withNote]);

    const inList = wrapper.find(
      '[data-test-id="recipe-tracking-provider-note"]'
    );
    expect(inList.exists()).toBe(true);
    expect(inList.text()).toContain('Salla cannot');

    await wrapper.find('[data-test-id="recipe-tracking-use"]').trigger('click');
    expect(
      wrapper.find('[data-test-id="recipe-selected-provider-note"]').exists()
    ).toBe(true);
  });

  it('says nothing about platforms for a starter that depends on none', async () => {
    const wrapper = await mountDialog([recipe('ready')]);

    expect(
      wrapper.find('[data-test-id="recipe-ready-provider-note"]').exists()
    ).toBe(false);
  });

  it('offers a usable recipe with a Use button', async () => {
    const wrapper = await mountDialog([recipe('ready')]);

    expect(wrapper.find('[data-test-id="recipe-ready-use"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-test-id="recipe-ready-requirements"]').exists()
    ).toBe(false);
  });

  it('says what is missing and offers no Create for a recipe the account cannot use', async () => {
    stores.value = [];
    const wrapper = await mountDialog([
      recipe('needs', { requires: [REQUIREMENTS.COMMERCE_STORE] }),
    ]);

    expect(wrapper.find('[data-test-id="recipe-needs-use"]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-test-id="recipe-needs-requirements"]').text()
    ).toBe('Needs a connected store first');
  });

  it('asks for the inputs the chosen recipe needs, and preselects a sole candidate', async () => {
    teams.value = [{ id: 7, name: 'Only team' }];
    const wrapper = await mountDialog([
      recipe('mapped', {
        inputs: [
          { key: 'team', type: INPUT_TYPES.TEAM, required: true },
          { key: 'currency', type: INPUT_TYPES.CURRENCY, required: true },
        ],
      }),
    ]);
    await wrapper.find('[data-test-id="recipe-mapped-use"]').trigger('click');

    expect(wrapper.find('[data-test-id="recipe-input-team"]').exists()).toBe(
      true
    );
    // One team, so it is filled in; two currencies, so it is not.
    expect(wrapper.vm.values).toEqual({ team: 7 });
  });

  it('refuses to create while a required value is missing, and says which', async () => {
    const wrapper = await mountDialog([
      recipe('needs_team', {
        inputs: [{ key: 'team', type: INPUT_TYPES.TEAM, required: true }],
      }),
    ]);
    await wrapper
      .find('[data-test-id="recipe-needs_team-use"]')
      .trigger('click');
    await wrapper.find('[data-test-id="recipe-create"]').trigger('click');

    expect(wrapper.emitted('create')).toBeUndefined();
    expect(wrapper.vm.errors).toEqual({ team: 'Choose a value' });
  });

  it('refuses a number outside the range the recipe declares', async () => {
    const wrapper = await mountDialog([
      recipe('days', {
        inputs: [
          {
            key: 'days',
            type: INPUT_TYPES.NUMBER,
            required: true,
            default: 30,
            min: 1,
            max: 998,
          },
        ],
      }),
    ]);
    await wrapper.find('[data-test-id="recipe-days-use"]').trigger('click');
    wrapper.vm.values.days = 1200;
    await wrapper.find('[data-test-id="recipe-create"]').trigger('click');

    expect(wrapper.emitted('create')).toBeUndefined();
    expect(wrapper.vm.errors.days).toBe('Enter a number between 1 and 998');
  });

  it('refuses an address that is not http or https', async () => {
    const wrapper = await mountDialog([
      recipe('hook', {
        inputs: [{ key: 'url', type: INPUT_TYPES.URL, required: true }],
      }),
    ]);
    await wrapper.find('[data-test-id="recipe-hook-use"]').trigger('click');
    // eslint-disable-next-line no-script-url
    wrapper.vm.values.url = 'javascript:alert(1)';
    await wrapper.find('[data-test-id="recipe-create"]').trigger('click');

    expect(wrapper.emitted('create')).toBeUndefined();
    expect(wrapper.vm.errors.url).toBe('Enter an http or https address');

    wrapper.vm.values.url = 'https://example.com/hook';
    await wrapper.find('[data-test-id="recipe-create"]').trigger('click');

    expect(wrapper.emitted('create')).toHaveLength(1);
  });

  it('hands the recipe and the values over once everything is valid', async () => {
    teams.value = [{ id: 7, name: 'Only team' }];
    const list = [
      recipe('ready', {
        inputs: [{ key: 'team', type: INPUT_TYPES.TEAM, required: true }],
      }),
    ];
    const wrapper = await mountDialog(list);
    await wrapper.find('[data-test-id="recipe-ready-use"]').trigger('click');
    await wrapper.find('[data-test-id="recipe-create"]').trigger('click');

    // The dialog hands over the recipe as this account sees it: the manifest plus its availability.
    const [[chosen, values]] = wrapper.emitted('create');
    expect(chosen).toMatchObject({ id: 'ready', status: 'available' });
    expect(chosen.build).toBe(list[0].build);
    expect(values).toEqual({ team: 7 });
  });

  it('keeps the recipe and the values after a failed create, so one field can be fixed', async () => {
    const wrapper = await mountDialog([
      recipe('ready', {
        inputs: [{ key: 'team', type: INPUT_TYPES.TEAM, required: true }],
      }),
    ]);
    await wrapper.find('[data-test-id="recipe-ready-use"]').trigger('click');
    wrapper.vm.values.team = 2;
    await wrapper.setProps({ isCreating: true });
    await wrapper.setProps({ isCreating: false });

    expect(wrapper.vm.selected.id).toBe('ready');
    expect(wrapper.vm.values).toEqual({ team: 2 });
    expect(wrapper.find('[data-test-id="recipe-input-team"]').exists()).toBe(
      true
    );
  });

  it('goes back to the gallery, and offers starting from scratch', async () => {
    const wrapper = await mountDialog([recipe('ready')]);
    await wrapper.find('[data-test-id="recipe-from-scratch"]').trigger('click');
    expect(wrapper.emitted('scratch')).toHaveLength(1);

    await wrapper.find('[data-test-id="recipe-ready-use"]').trigger('click');
    expect(wrapper.find('[data-test-id="recipe-ready-use"]').exists()).toBe(
      false
    );

    await wrapper.find('[data-test-id="recipe-back"]').trigger('click');
    expect(wrapper.find('[data-test-id="recipe-ready-use"]').exists()).toBe(
      true
    );
  });

  it('creates a recipe that needs nothing without asking anything', async () => {
    const list = [recipe('nothing')];
    const wrapper = await mountDialog(list);
    await wrapper.find('[data-test-id="recipe-nothing-use"]').trigger('click');

    expect(wrapper.text()).toContain('this one is ready to create');
    await wrapper.find('[data-test-id="recipe-create"]').trigger('click');

    const [[chosen, values]] = wrapper.emitted('create');
    expect(chosen.id).toBe('nothing');
    expect(values).toEqual({});
  });
});
