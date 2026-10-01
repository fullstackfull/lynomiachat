import { ref } from 'vue';
import CommerceAPI from 'dashboard/api/commerce';
import { useMapGetter } from 'dashboard/composables/store.js';
import {
  useAudienceFilterTypes,
  audienceValuesForEdit,
  COMMERCE_ORDER_KEY,
} from '../audienceProvider';
import { groupFilterTypes } from '../helper/filterAttributeIcons';

const commerceOn = ref(true);
const accountId = ref(1);

vi.mock('dashboard/api/commerce', () => ({
  default: { getAudienceFields: vi.fn() },
}));
vi.mock('dashboard/composables/store.js', () => ({ useMapGetter: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId,
    isCloudFeatureEnabled: () => commerceOn.value,
  }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params = {}) =>
      params.currency ? `${key}:${params.currency}` : key,
  }),
}));

const FIELDS = {
  stores: [
    { id: 4, name: 'Syria Cosmetics', provider: 'woocommerce' },
    { id: 9, name: 'Damascus', provider: 'woocommerce' },
  ],
  currencies: ['SAR', 'USD'],
  unread_contacts: 14,
};

describe('useAudienceFilterTypes', () => {
  beforeEach(() => {
    commerceOn.value = true;
    accountId.value += 1;
    useMapGetter.mockImplementation(() =>
      ref([{ id: 1, name: 'One', title: 'vip' }])
    );
    CommerceAPI.getAudienceFields.mockResolvedValue({ data: FIELDS });
  });

  it('offers conversation fields, and Commerce fields once the account options are loaded', async () => {
    const { audienceFilterTypes, loadAudienceFields, unreadContacts } =
      useAudienceFilterTypes();
    expect(audienceFilterTypes.value.map(type => type.attributeModel)).toEqual(
      Array(6).fill('conversation')
    );

    await loadAudienceFields();
    const keys = audienceFilterTypes.value.map(type => type.attributeKey);

    expect(keys).toEqual(
      expect.arrayContaining([
        'commerce_store',
        'commerce_provider',
        'commerce_orders_count',
        'commerce_spend_sar',
        'commerce_spend_usd',
        'commerce_last_purchase_at',
        'commerce_order_status',
      ])
    );
    const spend = audienceFilterTypes.value.find(
      type => type.attributeKey === 'commerce_spend_sar'
    );
    expect(spend.attributeName).toBe(
      'CONTACTS_FILTER.AUDIENCE.FIELDS.SPEND:SAR'
    );
    expect(spend.filterOperators.map(operator => operator.value)).toEqual([
      'is_greater_than',
      'is_less_than',
    ]);
    const provider = audienceFilterTypes.value.find(
      type => type.attributeKey === 'commerce_provider'
    );
    expect(provider.options).toEqual([
      { id: 'woocommerce', name: 'COMMERCE.PROVIDERS.WOOCOMMERCE' },
    ]);
    expect(unreadContacts.value).toBe(14);
    expect(CommerceAPI.getAudienceFields).toHaveBeenCalledTimes(1);

    await loadAudienceFields();
    expect(CommerceAPI.getAudienceFields).toHaveBeenCalledTimes(1);
  });

  it('offers no Commerce field to an account without Lynomia Commerce, and never asks for its options', async () => {
    commerceOn.value = false;
    const { audienceFilterTypes, loadAudienceFields } =
      useAudienceFilterTypes();

    await loadAudienceFields();

    expect(CommerceAPI.getAudienceFields).not.toHaveBeenCalled();
    expect(
      audienceFilterTypes.value.some(type => type.attributeModel === 'commerce')
    ).toBe(false);
  });

  it('keeps every other field when the Commerce options cannot be loaded', async () => {
    CommerceAPI.getAudienceFields.mockRejectedValue(new Error('offline'));
    const { audienceFilterTypes, loadAudienceFields } =
      useAudienceFilterTypes();

    await loadAudienceFields();

    expect(audienceFilterTypes.value).toHaveLength(6);
  });

  it('groups the fields under Conversations and Commerce in the picker', async () => {
    const { audienceFilterTypes, loadAudienceFields } =
      useAudienceFilterTypes();
    await loadAudienceFields();

    const headers = groupFilterTypes(
      audienceFilterTypes.value,
      key => key,
      'CONTACTS_FILTER'
    ).filter(entry => entry.disabled);

    expect(headers.map(header => header.label)).toEqual([
      'CONTACTS_FILTER.GROUPS.CONVERSATIONS',
      'CONTACTS_FILTER.GROUPS.COMMERCE',
    ]);
  });
});

describe('audienceValuesForEdit', () => {
  const stores = {
    inputType: 'multiSelect',
    options: [
      { id: 4, name: 'Syria Cosmetics' },
      { id: 9, name: 'Damascus' },
    ],
  };

  it('rebuilds the options a saved condition selected, whatever the id type', () => {
    expect(audienceValuesForEdit(stores, ['9'])).toEqual([
      { id: 9, name: 'Damascus' },
    ]);
    expect(
      audienceValuesForEdit(
        {
          inputType: 'searchSelect',
          options: [
            { id: 'true', name: 'Yes' },
            { id: 'false', name: 'No' },
          ],
        },
        [true]
      )
    ).toEqual({ id: 'true', name: 'Yes' });
    expect(audienceValuesForEdit({ inputType: 'number' }, [1000])).toBe('1000');
  });
});

describe('COMMERCE_ORDER_KEY', () => {
  it('names the fields that depend on read orders, not store or provider', () => {
    expect(COMMERCE_ORDER_KEY.test('commerce_spend_sar')).toBe(true);
    expect(COMMERCE_ORDER_KEY.test('commerce_orders_count')).toBe(true);
    expect(COMMERCE_ORDER_KEY.test('commerce_store')).toBe(false);
    expect(COMMERCE_ORDER_KEY.test('commerce_provider')).toBe(false);
  });
});
