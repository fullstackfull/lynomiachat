import { ref, reactive } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import {
  useLynomiaAutomation,
  COMMERCE_EVENTS,
  TEMPLATE_ACTION,
  isCommerceEvent,
} from './lynomiaAutomation';
import { AUTOMATIONS } from './constants';

const commerceOn = ref(true);
const dispatch = vi.fn().mockResolvedValue();
const loadAudienceFields = vi.fn().mockResolvedValue();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: vi.fn(),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => commerceOn.value }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/components-next/filter/audienceProvider', () => ({
  useAudienceFilterTypes: () => ({
    loadAudienceFields,
    audienceFilterTypes: ref([
      {
        attributeKey: 'conversation_status',
        attributeModel: 'conversation',
        inputType: 'multiSelect',
        filterOperators: [{ value: 'equal_to' }],
      },
      {
        attributeKey: 'commerce_store',
        attributeName: 'Linked store',
        attributeModel: 'commerce',
        inputType: 'multiSelect',
        options: [{ id: 4, name: 'Syria Cosmetics' }],
        filterOperators: [{ value: 'equal_to' }, { value: 'is_present' }],
      },
      {
        attributeKey: 'commerce_provider',
        attributeName: 'Store platform',
        attributeModel: 'commerce',
        inputType: 'multiSelect',
        options: [{ id: 'woocommerce', name: 'WooCommerce' }],
        filterOperators: [{ value: 'equal_to' }],
      },
      {
        attributeKey: 'commerce_spend_sar',
        attributeName: 'Visible spend (SAR)',
        attributeModel: 'commerce',
        inputType: 'number',
        filterOperators: [{ value: 'is_greater_than' }],
      },
    ]),
  }),
}));

const whatsappInboxes = ref([{ id: 7, name: 'KW Pharmacy' }]);

describe('useLynomiaAutomation', () => {
  beforeEach(() => {
    commerceOn.value = true;
    whatsappInboxes.value = [{ id: 7, name: 'KW Pharmacy' }];
    useMapGetter.mockImplementation(name =>
      name === 'inboxes/getWhatsAppInboxes'
        ? whatsappInboxes
        : ref([
            { id: 1, name: 'VIP', shared: true },
            { id: 2, name: 'Mine', shared: false },
          ])
    );
  });

  it('appends Audience and Commerce groups to every trigger and adds the Commerce triggers', () => {
    const { manifest } = useLynomiaAutomation();
    const types = reactive(structuredClone(AUTOMATIONS));

    manifest(types);
    manifest(types);

    COMMERCE_EVENTS.forEach(event => expect(types[event]).toBeDefined());
    const keys = types.conversation_created.conditions.map(c => c.key);
    expect(keys).toEqual(
      expect.arrayContaining([
        'status',
        'contact_audience',
        'commerce_store',
        'commerce_spend_sar',
      ])
    );
    expect(keys.filter(key => key === 'contact_audience')).toHaveLength(1);
    expect(keys).not.toContain('commerce_event_store');
    expect(keys).not.toContain('conversation_status');

    const commerceKeys = types.commerce_order_shipped.conditions.map(
      c => c.key
    );
    expect(commerceKeys).toEqual(
      expect.arrayContaining([
        'status',
        'commerce_event_store',
        'commerce_event_provider',
      ])
    );
    const spend = types.commerce_order_shipped.conditions.find(
      condition => condition.key === 'commerce_spend_sar'
    );
    expect(spend).toMatchObject({
      inputType: 'plain_text',
      name: 'Visible spend (SAR)',
      translated: true,
    });
  });

  it('offers only shared audiences, and the event conditions the store options', () => {
    const { conditionOptions } = useLynomiaAutomation();

    expect(conditionOptions('contact_audience')).toEqual([
      { id: 1, name: 'VIP' },
    ]);
    expect(conditionOptions('commerce_event_store')).toEqual([
      { id: 4, name: 'Syria Cosmetics' },
    ]);
    expect(conditionOptions('commerce_event_provider')).toEqual([
      { id: 'woocommerce', name: 'WooCommerce' },
    ]);
    expect(conditionOptions('status')).toBeUndefined();
  });

  it('offers no Commerce trigger or field without Lynomia Commerce, only the audience', () => {
    commerceOn.value = false;
    const { manifest, events } = useLynomiaAutomation();
    const types = reactive(structuredClone(AUTOMATIONS));

    manifest(types);

    expect(events.value).toEqual([]);
    expect(types.commerce_order_paid).toBeUndefined();
    const keys = types.message_created.conditions.map(c => c.key);
    expect(keys).toContain('contact_audience');
    expect(keys.some(key => key.startsWith('commerce_'))).toBe(false);
  });

  it('keeps customer messages out of Commerce triggers only', () => {
    const { actionAllowed } = useLynomiaAutomation();

    expect(actionAllowed('commerce_order_shipped', 'send_message')).toBe(false);
    expect(actionAllowed('commerce_order_shipped', 'send_attachment')).toBe(
      false
    );
    expect(actionAllowed('commerce_order_shipped', 'add_label')).toBe(true);
    expect(actionAllowed('conversation_created', 'send_message')).toBe(true);
    expect(isCommerceEvent('conversation_created')).toBe(false);
  });

  it('loads shared audiences and the Commerce options', async () => {
    const { load } = useLynomiaAutomation();

    await load();

    expect(dispatch).toHaveBeenCalledWith('customViews/get', 'contact');
    expect(loadAudienceFields).toHaveBeenCalled();
  });

  describe('the approved WhatsApp template action', () => {
    it('includes the abandoned cart trigger among the Commerce triggers', () => {
      expect(COMMERCE_EVENTS).toContain('commerce_cart_abandoned');
      expect(isCommerceEvent('commerce_cart_abandoned')).toBe(true);
    });

    it('is offered on a Commerce trigger, because an approved template is not a free-form message', () => {
      const { actionAllowed } = useLynomiaAutomation();

      expect(actionAllowed('commerce_cart_abandoned', TEMPLATE_ACTION)).toBe(
        true
      );
      expect(actionAllowed('commerce_order_paid', TEMPLATE_ACTION)).toBe(true);
    });

    it('still refuses a free-form customer message on a Commerce trigger', () => {
      const { actionAllowed } = useLynomiaAutomation();

      expect(actionAllowed('commerce_cart_abandoned', 'send_message')).toBe(
        false
      );
      expect(actionAllowed('commerce_cart_abandoned', 'send_attachment')).toBe(
        false
      );
    });

    // Offering an action that cannot be configured is the invisible no-op this project keeps guarding against.
    it('is not offered at all when the account has no WhatsApp inbox', () => {
      whatsappInboxes.value = [];
      const { actionAllowed } = useLynomiaAutomation();

      expect(actionAllowed('commerce_cart_abandoned', TEMPLATE_ACTION)).toBe(
        false
      );
      expect(actionAllowed('conversation_created', TEMPLATE_ACTION)).toBe(
        false
      );
    });

    it('leaves every other action alone', () => {
      const { actionAllowed } = useLynomiaAutomation();

      expect(actionAllowed('conversation_created', 'add_label')).toBe(true);
      expect(actionAllowed('commerce_cart_abandoned', 'add_label')).toBe(true);
    });
  });
});
