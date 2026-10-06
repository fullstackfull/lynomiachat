// Every automation recipe checked against the rule contract the create endpoint and the model enforce:
// `app/controllers/api/v1/accounts/automation_rules_controller.rb` (permitted keys),
// `app/models/automation_rule.rb` (condition and action vocabulary, query operators) and
// `custom/app/models/custom/automation_rule.rb` (Lynomia's own rules for Commerce triggers).
import { AUTOMATION_RECIPES } from '../automationRecipes';
import { INPUT_TYPES, REQUIREMENTS } from '../index';

// Custom::AutomationRule#conditions_attributes = Chatwoot's list plus the Lynomia keys.
const CHATWOOT_CONDITIONS = [
  'content',
  'email',
  'country_code',
  'status',
  'message_type',
  'browser_language',
  'assignee_id',
  'team_id',
  'referer',
  'city',
  'company_name',
  'inbox_id',
  'mail_subject',
  'phone_number',
  'priority',
  'conversation_language',
  'labels',
  'private_note',
];
const LYNOMIA_CONDITIONS = [
  'contact_audience',
  'commerce_event_store',
  'commerce_event_provider',
  'commerce_store',
  'commerce_provider',
  'commerce_orders_count',
  'commerce_last_purchase_at',
  'commerce_active_order',
  'commerce_order_status',
  'commerce_payment_status',
  'commerce_shipment_status',
];
const SPEND = /^commerce_spend_[a-z]{3}$/;
// AutomationRule#actions_attributes
const ACTIONS = [
  'send_message',
  'add_label',
  'remove_label',
  'send_email_to_team',
  'assign_team',
  'assign_agent',
  'remove_assigned_agent',
  'remove_assigned_team',
  'send_webhook_event',
  'mute_conversation',
  'send_attachment',
  'change_status',
  'resolve_conversation',
  'open_conversation',
  'pending_conversation',
  'snooze_conversation',
  'change_priority',
  'send_email_transcript',
  'add_private_note',
  // Lynomia: the one customer-facing action a Commerce trigger may use, because an approved template is the
  // only thing WhatsApp permits outside the 24-hour window (custom/app/models/custom/automation_rule.rb).
  'send_whatsapp_template',
];
// Commerce::OrderTransitions::EVENTS
const COMMERCE_EVENTS = [
  'commerce_order_created',
  'commerce_order_updated',
  'commerce_order_paid',
  'commerce_order_shipped',
  'commerce_order_delivered',
  'commerce_order_cancelled',
  'commerce_order_refunded',
  'commerce_cart_abandoned',
];
// Custom::AutomationRule::CUSTOMER_MESSAGE_ACTIONS: never offered on a Commerce trigger.
const CUSTOMER_MESSAGE_ACTIONS = ['send_message', 'send_attachment'];
const PRIORITIES = ['low', 'medium', 'high', 'urgent'];
const PERMITTED_CONDITION_KEYS = [
  'attribute_key',
  'custom_attribute_type',
  'filter_operator',
  'query_operator',
  'values',
];

const VALUES = {
  store: 4,
  team: 3,
  audience: 9,
  labels: ['vip'],
  currency: 'SAR',
  amount: 1000,
  priority: 'high',
  event: 'commerce_order_paid',
  url: 'https://example.com/hook',
};

const byId = id => AUTOMATION_RECIPES.find(item => item.id === id);
const built = (values = VALUES) =>
  AUTOMATION_RECIPES.map(item => [item, item.build(values)]);

describe('AUTOMATION_RECIPES', () => {
  it('declares a complete manifest for every recipe', () => {
    AUTOMATION_RECIPES.forEach(item => {
      expect(item.type).toBe('automation');
      expect(item.id).toMatch(/^[a-z][a-z0-9_]*$/);
      expect(item.version).toBe(1);
      expect(item.name).toBe(
        `RECIPES.AUTOMATION.${item.id.toUpperCase()}.NAME`
      );
      expect(item.description).toBe(
        `RECIPES.AUTOMATION.${item.id.toUpperCase()}.DESCRIPTION`
      );
      expect(item.requires).toContain(REQUIREMENTS.AUTOMATIONS);
      item.inputs.forEach(input =>
        expect(Object.values(INPUT_TYPES)).toContain(input.type)
      );
    });
  });

  it('uses unique ids', () => {
    const ids = AUTOMATION_RECIPES.map(item => item.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('creates every rule switched off', () => {
    built().forEach(([item, rule]) =>
      expect([item.id, rule.active]).toEqual([item.id, false])
    );
  });

  it('leaves naming to the page that creates it', () => {
    built().forEach(([item, rule]) =>
      expect(Object.keys(rule).sort(), item.id).toEqual([
        'actions',
        'active',
        'conditions',
        'event_name',
      ])
    );
  });

  it('sends only condition keys the endpoint permits', () => {
    built().forEach(([item, rule]) =>
      rule.conditions.forEach(condition =>
        expect(
          Object.keys(condition).filter(
            key => !PERMITTED_CONDITION_KEYS.includes(key)
          ),
          item.id
        ).toEqual([])
      )
    );
  });

  it('names only conditions the rule model accepts', () => {
    built().forEach(([item, rule]) =>
      rule.conditions.forEach(condition => {
        const known =
          CHATWOOT_CONDITIONS.includes(condition.attribute_key) ||
          LYNOMIA_CONDITIONS.includes(condition.attribute_key) ||
          SPEND.test(condition.attribute_key);
        expect(known, `${item.id}: ${condition.attribute_key}`).toBe(true);
      })
    );
  });

  it('names only actions the rule model accepts, and fills every action it can', () => {
    built().forEach(([item, rule]) =>
      rule.actions.forEach(action => {
        expect(ACTIONS, item.id).toContain(action.action_name);
        expect(Array.isArray(action.action_params), item.id).toBe(true);
        // The approved-template action is the one a recipe deliberately leaves empty: its inbox, template and
        // variable mapping are chosen in the rule editor, where the real control lives, rather than duplicating a
        // template selector into this wizard. The rule is created disabled and
        // Custom::AutomationRule#template_action_configured refuses to switch on an incomplete one, so an empty
        // action here can never run.
        if (action.action_name === 'send_whatsapp_template') return;

        expect(
          action.action_params.length,
          `${item.id}/${action.action_name}`
        ).toBeGreaterThan(0);
      })
    );
  });

  // The abandoned-cart starter, and the properties that make it safe to ship while Zid cart ingestion is PRE_UAT.
  it('ships the abandoned-cart starter disabled, on the cart trigger, with only the approved-template action', () => {
    const [item, rule] = built().find(
      ([recipe]) => recipe.id === 'commerce_abandoned_cart_template'
    );

    expect(rule.event_name).toBe('commerce_cart_abandoned');
    expect(rule.active).toBe(false);
    expect(rule.actions.map(action => action.action_name)).toEqual([
      'send_whatsapp_template',
    ]);
    expect(item.inputs.map(input => input.key)).toEqual(['store']);
    expect(item.providerNote).toBeTruthy();
  });

  it('gives at most one condition a null query operator, as the model requires', () => {
    built().forEach(([item, rule]) => {
      expect(rule.conditions.length, item.id).toBeGreaterThan(0);
      expect(
        rule.conditions.filter(condition => condition.query_operator === null)
          .length,
        item.id
      ).toBe(1);
      expect(rule.conditions.at(-1).query_operator, item.id).toBeNull();
      rule.conditions
        .slice(0, -1)
        .forEach(condition =>
          expect(condition.query_operator, item.id).toBe('and')
        );
    });
  });

  it('never sends a customer message on a Commerce trigger', () => {
    built().forEach(([item, rule]) => {
      if (!COMMERCE_EVENTS.includes(rule.event_name)) return;
      rule.actions.forEach(action =>
        expect(CUSTOMER_MESSAGE_ACTIONS, item.id).not.toContain(
          action.action_name
        )
      );
    });
  });

  it('never asks for a delay, which a Commerce trigger refuses', () => {
    built().forEach(([item, rule]) =>
      expect(rule.execution_delay, item.id).toBeUndefined()
    );
  });

  it('uses the event-store condition only on a Commerce trigger', () => {
    built().forEach(([item, rule]) => {
      const eventConditions = rule.conditions.filter(condition =>
        ['commerce_event_store', 'commerce_event_provider'].includes(
          condition.attribute_key
        )
      );
      if (eventConditions.length) {
        expect(COMMERCE_EVENTS, item.id).toContain(rule.event_name);
      }
    });
  });

  it('asks for Commerce only when it needs Commerce data', () => {
    built().forEach(([item, rule]) => {
      const usesCommerce =
        COMMERCE_EVENTS.includes(rule.event_name) ||
        rule.conditions.some(
          condition =>
            condition.attribute_key.startsWith('commerce_') ||
            SPEND.test(condition.attribute_key)
        );
      expect(item.requires.includes(REQUIREMENTS.COMMERCE), item.id).toBe(
        usesCommerce
      );
    });
  });

  it('asks for a shared audience only when it references one', () => {
    built().forEach(([item, rule]) => {
      const usesAudience = rule.conditions.some(
        condition => condition.attribute_key === 'contact_audience'
      );
      expect(
        item.requires.includes(REQUIREMENTS.SHARED_AUDIENCE),
        item.id
      ).toBe(usesAudience);
    });
  });

  it('builds the new-order recipe on the store the user chose', () => {
    expect(byId('commerce_new_order_routing').build(VALUES)).toEqual({
      event_name: 'commerce_order_created',
      conditions: [
        {
          attribute_key: 'commerce_event_store',
          filter_operator: 'equal_to',
          values: [4],
          query_operator: null,
        },
      ],
      actions: [
        { action_name: 'add_label', action_params: ['vip'] },
        { action_name: 'assign_team', action_params: [3] },
      ],
      active: false,
    });
  });

  it('escalates a refund with a priority the engine knows', () => {
    const rule = byId('commerce_refund_escalation').build(VALUES);

    expect(rule.event_name).toBe('commerce_order_refunded');
    const priority = rule.actions.find(
      action => action.action_name === 'change_priority'
    );
    expect(PRIORITIES).toContain(priority.action_params[0]);
  });

  it('asks which currency a spend rule means and never converts', () => {
    const recipe = byId('high_value_spend_routing');
    expect(recipe.inputs.map(input => input.key)).toEqual([
      'currency',
      'amount',
      'team',
      'labels',
    ]);

    expect(
      recipe.build({ ...VALUES, currency: 'AED', amount: 250 }).conditions[0]
    ).toEqual({
      attribute_key: 'commerce_spend_aed',
      filter_operator: 'is_greater_than',
      values: ['250'],
      query_operator: null,
    });
  });

  it('only offers a Commerce event the engine really dispatches', () => {
    const recipe = byId('commerce_event_webhook');
    COMMERCE_EVENTS.forEach(event =>
      expect(recipe.build({ ...VALUES, event }).event_name).toBe(event)
    );
  });

  it('adds no label action when the user chose no label', () => {
    built({ ...VALUES, labels: [] }).forEach(([item, rule]) => {
      // A recipe whose whole point is the label asks for one, and the wizard will not let it through empty.
      const labelsRequired = item.inputs.some(
        input => input.key === 'labels' && input.required
      );
      if (labelsRequired) return;

      expect(
        rule.actions.map(action => action.action_name),
        item.id
      ).not.toContain('add_label');
    });
  });
});
