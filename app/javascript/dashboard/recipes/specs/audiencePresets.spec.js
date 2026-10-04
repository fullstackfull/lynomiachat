import { AUDIENCE_PRESETS } from '../audiencePresets';
import { INPUT_TYPES, RECIPE_STATUS, REQUIREMENTS } from '../index';

const byId = id => AUDIENCE_PRESETS.find(preset => preset.id === id);
const build = (id, values = {}) => byId(id).build(values).payload;

describe('AUDIENCE_PRESETS', () => {
  it('declares a complete manifest for every preset', () => {
    AUDIENCE_PRESETS.forEach(preset => {
      expect(preset.type).toBe('audience');
      expect(preset.id).toMatch(/^[a-z][a-z0-9_]*$/);
      expect(preset.version).toBe(1);
      expect(preset.name).toBe(
        `RECIPES.AUDIENCE.${preset.id.toUpperCase()}.NAME`
      );
      expect(preset.description).toBe(
        `RECIPES.AUDIENCE.${preset.id.toUpperCase()}.DESCRIPTION`
      );
      expect(preset.requires).toContain(REQUIREMENTS.CONTACT_FILTER);
      expect(typeof preset.build).toBe('function');
    });
  });

  it('uses unique ids', () => {
    const ids = AUDIENCE_PRESETS.map(preset => preset.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('builds conditions in the shape the filter builder saves, with no operator on the last one', () => {
    build('customers_with_active_order').forEach((condition, index, all) => {
      expect(Object.keys(condition).sort()).toEqual([
        'attribute_key',
        'attribute_model',
        'filter_operator',
        'query_operator',
        'values',
      ]);
      expect(condition.attribute_model).toBe('commerce');
      expect(condition.query_operator).toBe(
        index === all.length - 1 ? null : 'and'
      );
    });
  });

  it('asks for the currency and never assumes one, and never converts', () => {
    const preset = byId('high_value_buyers');
    expect(preset.inputs.map(input => input.type)).toEqual([
      INPUT_TYPES.CURRENCY,
      INPUT_TYPES.NUMBER,
    ]);
    expect(preset.inputs.every(input => input.required)).toBe(true);

    expect(
      build('high_value_buyers', { currency: 'SAR', amount: 1000 })
    ).toEqual([
      {
        attribute_key: 'commerce_spend_sar',
        filter_operator: 'is_greater_than',
        attribute_model: 'commerce',
        values: ['1000'],
        query_operator: null,
      },
    ]);
    expect(
      build('high_value_buyers', { currency: 'AED', amount: 500 })[0]
        .attribute_key
    ).toBe('commerce_spend_aed');
  });

  it('builds the remaining presets on fields and operators Commerce really has', () => {
    expect(build('repeat_buyers', { orders: 2 })[0]).toMatchObject({
      attribute_key: 'commerce_orders_count',
      filter_operator: 'is_greater_than',
      values: ['2'],
    });
    expect(build('recent_buyers', { days: 30 })[0]).toMatchObject({
      attribute_key: 'commerce_last_purchase_at',
      filter_operator: 'days_before',
      values: ['30'],
    });
    expect(build('customers_with_active_order')[0]).toMatchObject({
      attribute_key: 'commerce_active_order',
      filter_operator: 'equal_to',
      values: ['true'],
    });
    // The order status, not the shipment status: the normalized shipment statuses have no "shipped".
    expect(build('customers_with_shipped_order')[0]).toMatchObject({
      attribute_key: 'commerce_order_status',
      filter_operator: 'equal_to',
      values: ['shipped'],
    });
    expect(build('store_customers', { store: 4 })[0]).toMatchObject({
      attribute_key: 'commerce_store',
      filter_operator: 'equal_to',
      values: ['4'],
    });
    expect(build('linked_commerce_customers')[0]).toMatchObject({
      attribute_key: 'commerce_store',
      filter_operator: 'is_present',
      values: [],
    });
  });

  it("keeps every condition inside the engine's own field and operator list", () => {
    const OPERATORS = {
      commerce_store: [
        'equal_to',
        'not_equal_to',
        'is_present',
        'is_not_present',
      ],
      commerce_provider: ['equal_to', 'not_equal_to'],
      commerce_orders_count: ['equal_to', 'is_greater_than', 'is_less_than'],
      commerce_last_purchase_at: [
        'is_greater_than',
        'is_less_than',
        'days_before',
      ],
      commerce_active_order: ['equal_to'],
      commerce_order_status: ['equal_to', 'not_equal_to'],
      commerce_payment_status: ['equal_to', 'not_equal_to'],
      commerce_shipment_status: ['equal_to', 'not_equal_to'],
      // Audience::ConversationCondition::FIELDS, with its own OPERATORS — equality only, compiled into an
      // EXISTS subquery over the contact's conversations.
      conversation_status: ['equal_to', 'not_equal_to'],
      conversation_priority: ['equal_to', 'not_equal_to'],
      conversation_inbox: ['equal_to', 'not_equal_to'],
      conversation_assignee: ['equal_to', 'not_equal_to'],
      conversation_team: ['equal_to', 'not_equal_to'],
      conversation_labels: ['equal_to', 'not_equal_to'],
    };
    const SPEND_OPERATORS = ['is_greater_than', 'is_less_than'];
    const sample = {
      currency: 'SAR',
      amount: 1,
      orders: 1,
      days: 1,
      store: 1,
    };

    AUDIENCE_PRESETS.forEach(preset => {
      preset.build(sample).payload.forEach(condition => {
        const allowed = /^commerce_spend_[a-z]{3}$/.test(
          condition.attribute_key
        )
          ? SPEND_OPERATORS
          : OPERATORS[condition.attribute_key];
        expect(allowed, condition.attribute_key).toBeDefined();
        expect(allowed).toContain(condition.filter_operator);
      });
    });
  });

  it('asks about conversation history on the conversation model, over every status', () => {
    const byId = Object.fromEntries(
      AUDIENCE_PRESETS.map(preset => [preset.id, preset.build({}).payload])
    );

    expect(byId.contacted_us).toEqual([
      {
        attribute_key: 'conversation_status',
        filter_operator: 'equal_to',
        attribute_model: 'conversation',
        values: ['open', 'pending', 'resolved', 'snoozed'],
        query_operator: null,
      },
    ]);
    // The mirror image, so "never" really is every status rather than one of them.
    expect(byId.never_contacted_us[0]).toMatchObject({
      filter_operator: 'not_equal_to',
      values: ['open', 'pending', 'resolved', 'snoozed'],
    });
  });

  it('needs nothing of the account for the conversation presets but a contact filter', () => {
    const conversationPresets = AUDIENCE_PRESETS.filter(preset =>
      ['contacted_us', 'never_contacted_us'].includes(preset.id)
    );

    conversationPresets.forEach(preset => {
      expect(preset.requires).toEqual(['contact_filter']);
      expect(preset.inputs).toEqual([]);
    });
  });

  it("stays within the engine's limit of ten audience conditions per filter", () => {
    AUDIENCE_PRESETS.forEach(preset => {
      expect(
        preset.build({
          currency: 'SAR',
          amount: 1,
          orders: 1,
          days: 1,
          store: 1,
        }).payload.length
      ).toBeLessThanOrEqual(10);
    });
  });

  it('exposes only requirements the context composable can answer', () => {
    const known = Object.values(REQUIREMENTS);
    AUDIENCE_PRESETS.forEach(preset =>
      preset.requires.forEach(key => expect(known).toContain(key))
    );
  });

  it('names only input types the wizard can render', () => {
    const known = Object.values(INPUT_TYPES);
    AUDIENCE_PRESETS.forEach(preset =>
      preset.inputs.forEach(input => expect(known).toContain(input.type))
    );
  });

  it('keeps the status vocabulary the gallery renders', () => {
    expect(Object.values(RECIPE_STATUS)).toEqual([
      'available',
      'requires_setup',
    ]);
  });
});
