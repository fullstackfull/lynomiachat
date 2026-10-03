import { ref, computed } from 'vue';
import { useRecipeContext } from '../useRecipeContext';
import { CATEGORIES, INPUT_TYPES, RECIPE_STATUS, REQUIREMENTS } from '../index';

const enabledFlags = ref([
  'crm',
  'lynomia_commerce',
  'lynomia_flow_builder',
  'automations',
  'api_and_webhooks',
]);
const store = ref({
  'teams/getTeams': [{ id: 1, name: 'Support' }],
  'labels/getLabels': [{ id: 1, title: 'vip' }],
  'customViews/getContactCustomViews': [
    { id: 3, name: 'VIP buyers', shared: true },
    { id: 4, name: 'Mine', shared: false },
  ],
  'inboxes/getWhatsAppInboxes': [{ id: 8, name: 'WhatsApp' }],
});
const stores = ref([
  { id: 4, name: 'Syria Cosmetics', provider: 'woocommerce' },
]);
const currencies = ref(['SAR']);
const loadAudienceFields = vi.fn();

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name => computed(() => store.value[name]),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => enabledFlags.value.includes(flag),
  }),
}));
vi.mock('dashboard/components-next/filter/audienceProvider', () => ({
  useAudienceFilterTypes: () => ({
    loadAudienceFields,
    commerceStores: computed(() => stores.value),
    commerceCurrencies: computed(() => currencies.value),
  }),
}));

const recipe = (id, requires, inputs = []) => ({
  id,
  type: 'audience',
  version: 1,
  name: id,
  description: id,
  category: CATEGORIES.ECOMMERCE,
  requires,
  inputs,
  build: () => ({}),
});

describe('useRecipeContext', () => {
  beforeEach(() => {
    enabledFlags.value = [
      'crm',
      'lynomia_commerce',
      'lynomia_flow_builder',
      'automations',
      'api_and_webhooks',
    ];
    stores.value = [
      { id: 4, name: 'Syria Cosmetics', provider: 'woocommerce' },
    ];
    currencies.value = ['SAR'];
  });

  it('collects the account options from what the dashboard already holds', () => {
    const { context } = useRecipeContext();

    expect(context.value.teams).toEqual([{ id: 1, name: 'Support' }]);
    expect(context.value.stores).toEqual(stores.value);
    expect(context.value.currencies).toEqual(['SAR']);
    // Only shared contact filters are audiences.
    expect(context.value.audiences.map(audience => audience.id)).toEqual([3]);
  });

  it('calls the Commerce options loader rather than fetching anything itself', async () => {
    const { loadCommerceOptions } = useRecipeContext();
    await loadCommerceOptions();

    expect(loadAudienceFields).toHaveBeenCalled();
  });

  it('marks a recipe available when the account meets every requirement', () => {
    const { describe: describeOne } = useRecipeContext();
    const described = describeOne(
      recipe('ok', [REQUIREMENTS.COMMERCE, REQUIREMENTS.COMMERCE_STORE])
    );

    expect(described.status).toBe(RECIPE_STATUS.AVAILABLE);
    expect(described.missing).toEqual([]);
  });

  it('says which requirement is missing instead of offering a broken configuration', () => {
    stores.value = [];
    currencies.value = [];
    const { describe: describeOne } = useRecipeContext();
    const described = describeOne(
      recipe('needs', [
        REQUIREMENTS.COMMERCE_STORE,
        REQUIREMENTS.COMMERCE_CURRENCY,
      ])
    );

    expect(described.status).toBe(RECIPE_STATUS.REQUIRES_SETUP);
    expect(described.missing).toEqual([
      REQUIREMENTS.COMMERCE_STORE,
      REQUIREMENTS.COMMERCE_CURRENCY,
    ]);
    expect(described.reasons).toEqual([
      'RECIPES.REQUIREMENTS.COMMERCE_STORE',
      'RECIPES.REQUIREMENTS.COMMERCE_CURRENCY',
    ]);
  });

  it('requires Commerce only when the account feature is on', () => {
    enabledFlags.value = ['crm'];
    const { describe: describeOne } = useRecipeContext();

    expect(describeOne(recipe('c', [REQUIREMENTS.COMMERCE])).status).toBe(
      RECIPE_STATUS.REQUIRES_SETUP
    );
    expect(describeOne(recipe('f', [REQUIREMENTS.FLOW_BUILDER])).status).toBe(
      RECIPE_STATUS.REQUIRES_SETUP
    );
    expect(describeOne(recipe('w', [REQUIREMENTS.WEBHOOKS])).status).toBe(
      RECIPE_STATUS.REQUIRES_SETUP
    );
    expect(describeOne(recipe('t', [REQUIREMENTS.TEAM])).status).toBe(
      RECIPE_STATUS.AVAILABLE
    );
  });

  it('treats a shared audience requirement as unmet when the account has none', () => {
    store.value['customViews/getContactCustomViews'] = [
      { id: 4, name: 'Mine', shared: false },
    ];
    const { describe: describeOne } = useRecipeContext();

    expect(
      describeOne(recipe('vip', [REQUIREMENTS.SHARED_AUDIENCE])).status
    ).toBe(RECIPE_STATUS.REQUIRES_SETUP);

    store.value['customViews/getContactCustomViews'] = [
      { id: 3, name: 'VIP buyers', shared: true },
    ];
  });

  it('puts usable recipes first, then the ones this account is set up for', () => {
    const { describeAll } = useRecipeContext();
    const ordered = describeAll([
      recipe('plain', []),
      recipe('needs_store', [REQUIREMENTS.SHARED_AUDIENCE, 'nope']),
      recipe('audience_based', [REQUIREMENTS.SHARED_AUDIENCE]),
      recipe('commerce_based', [REQUIREMENTS.COMMERCE]),
    ]);

    expect(ordered.map(item => item.id)).toEqual([
      'commerce_based',
      'audience_based',
      'plain',
      'needs_store',
    ]);
    expect(ordered.at(-1).status).toBe(RECIPE_STATUS.REQUIRES_SETUP);
  });

  it('does not reorder Commerce recipes first for an account with no connected store', () => {
    stores.value = [];
    const { describeAll } = useRecipeContext();
    const ordered = describeAll([
      recipe('plain', []),
      recipe('commerce_based', [REQUIREMENTS.COMMERCE]),
    ]);

    expect(ordered.map(item => item.id)).toEqual(['plain', 'commerce_based']);
  });

  it('fills in a sole team, store, currency or audience, and a declared default', () => {
    const { presetValues } = useRecipeContext();
    const values = presetValues(
      recipe(
        'mapped',
        [],
        [
          { key: 'team', type: INPUT_TYPES.TEAM, required: true },
          { key: 'store', type: INPUT_TYPES.STORE, required: true },
          { key: 'currency', type: INPUT_TYPES.CURRENCY, required: true },
          { key: 'audience', type: INPUT_TYPES.AUDIENCE, required: true },
          {
            key: 'days',
            type: INPUT_TYPES.NUMBER,
            required: true,
            default: 30,
          },
        ]
      )
    );

    expect(values).toEqual({
      team: 1,
      store: 4,
      currency: 'SAR',
      audience: 3,
      days: 30,
    });
  });

  it('fills in nothing when the account leaves a real choice, and never a webhook address', () => {
    store.value['teams/getTeams'] = [
      { id: 1, name: 'Support' },
      { id: 2, name: 'Sales' },
    ];
    currencies.value = ['SAR', 'AED'];
    const { presetValues } = useRecipeContext();
    const values = presetValues(
      recipe(
        'open',
        [],
        [
          { key: 'team', type: INPUT_TYPES.TEAM, required: true },
          { key: 'currency', type: INPUT_TYPES.CURRENCY, required: true },
          { key: 'url', type: INPUT_TYPES.URL, required: true },
          { key: 'labels', type: INPUT_TYPES.LABELS, required: false },
        ]
      )
    );

    expect(values).toEqual({});
    store.value['teams/getTeams'] = [{ id: 1, name: 'Support' }];
  });
});
