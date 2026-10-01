import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import CommerceAPI from 'dashboard/api/commerce';
import { useOperators } from './operators';

// Lynomia Audience (docs/audience/02-audience-architecture.md): the conversation and Commerce fields of the contact
// filter, in the same attribute picker, with the operators Chatwoot already has. Conversation fields match contacts
// with, or without, such a conversation; Commerce fields read only what Lynomia stored, never a store.

export const ORDER_STATUSES = [
  'pending',
  'processing',
  'on_hold',
  'shipped',
  'delivered',
  'completed',
  'cancelled',
  'refunded',
  'failed',
  'draft',
  'other',
];
export const PAYMENT_STATUSES = [
  'paid',
  'unpaid',
  'partially_paid',
  'failed',
  'refunded',
  'partially_refunded',
  'unknown',
];
export const SHIPMENT_STATUSES = [
  'pending',
  'in_transit',
  'out_for_delivery',
  'delivered',
  'failed',
  'cancelled',
  'returned',
  'other',
];

// Fields whose answer depends on orders Lynomia has read: unknown for linked contacts not read yet.
export const COMMERCE_ORDER_KEY =
  /^commerce_(orders_count|spend_[a-z]{3}|last_purchase_at|active_order|order_status|payment_status|shipment_status)$/;

// The Commerce options of the current account (stores, currencies seen, contacts not read yet), loaded once per account.
const commerceFields = ref(null);

export function useAudienceFilterTypes() {
  const { t } = useI18n();
  const { accountId, isCloudFeatureEnabled } = useAccount();
  const labels = useMapGetter('labels/getLabels');
  const agents = useMapGetter('agents/getAgents');
  const inboxes = useMapGetter('inboxes/getInboxes');
  const teams = useMapGetter('teams/getTeams');
  const { operators, equalityOperators, presenceOperators, dateOperators } =
    useOperators();

  const isCommerceEnabled = computed(() =>
    isCloudFeatureEnabled(FEATURE_FLAGS.LYNOMIA_COMMERCE)
  );

  const loadAudienceFields = async () => {
    if (!isCommerceEnabled.value) return;
    if (commerceFields.value?.accountId === accountId.value) return;

    try {
      const { data } = await CommerceAPI.getAudienceFields();
      commerceFields.value = { ...data, accountId: accountId.value };
    } catch {
      // Without its options the builder offers no Commerce fields; every other field still works.
    }
  };

  const field = (attributeKey, name, attributeModel, rest) => ({
    attributeKey,
    value: attributeKey,
    attributeName: name,
    label: name,
    dataType: 'text',
    attributeModel,
    ...rest,
  });
  const pick = keys => keys.map(key => operators.value[key]);
  // Commerce's own labels for providers and normalized statuses.
  const optionsOf = (list, prefix) =>
    list.map(id => ({ id, name: t(`COMMERCE.${prefix}.${id.toUpperCase()}`) }));
  const named = list => list.map(({ id, name }) => ({ id, name }));

  const conversationTypes = computed(() => {
    const multi = (key, name, options) =>
      field(key, name, 'conversation', {
        inputType: 'multiSelect',
        options,
        filterOperators: equalityOperators.value,
      });
    return [
      multi(
        'conversation_status',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.CONVERSATION_STATUS'),
        ['open', 'resolved', 'pending', 'snoozed'].map(id => ({
          id,
          name: t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${id}.TEXT`),
        }))
      ),
      multi(
        'conversation_priority',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.CONVERSATION_PRIORITY'),
        ['low', 'medium', 'high', 'urgent'].map(id => ({
          id,
          name: t(`CONVERSATION.PRIORITY.OPTIONS.${id.toUpperCase()}`),
        }))
      ),
      multi(
        'conversation_inbox',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.CONVERSATION_INBOX'),
        named(inboxes.value)
      ),
      multi(
        'conversation_assignee',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.CONVERSATION_ASSIGNEE'),
        named(agents.value)
      ),
      multi(
        'conversation_team',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.CONVERSATION_TEAM'),
        named(teams.value)
      ),
      multi(
        'conversation_labels',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.CONVERSATION_LABELS'),
        (labels.value || []).map(({ title }) => ({ id: title, name: title }))
      ),
    ];
  });

  const commerceTypes = computed(() => {
    const fields = commerceFields.value;
    if (!isCommerceEnabled.value || fields?.accountId !== accountId.value) {
      return [];
    }

    const commerce = (key, name, rest) => field(key, name, 'commerce', rest);
    const number = (key, name, ops) =>
      commerce(key, name, { inputType: 'number', filterOperators: pick(ops) });
    const providers = [...new Set(fields.stores.map(store => store.provider))];

    return [
      commerce('commerce_store', t('CONTACTS_FILTER.AUDIENCE.FIELDS.STORE'), {
        inputType: 'multiSelect',
        options: named(fields.stores),
        filterOperators: presenceOperators.value,
      }),
      commerce(
        'commerce_provider',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.PROVIDER'),
        {
          inputType: 'multiSelect',
          options: optionsOf(providers, 'PROVIDERS'),
          filterOperators: equalityOperators.value,
        }
      ),
      number(
        'commerce_orders_count',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.ORDERS'),
        ['equal_to', 'is_greater_than', 'is_less_than']
      ),
      ...fields.currencies.map(currency =>
        number(
          `commerce_spend_${currency.toLowerCase()}`,
          t('CONTACTS_FILTER.AUDIENCE.FIELDS.SPEND', { currency }),
          ['is_greater_than', 'is_less_than']
        )
      ),
      commerce(
        'commerce_last_purchase_at',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.LAST_PURCHASE'),
        { inputType: 'date', filterOperators: dateOperators.value }
      ),
      commerce(
        'commerce_active_order',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.ACTIVE_ORDER'),
        {
          inputType: 'searchSelect',
          options: [
            { id: 'true', name: t('CONTACTS_FILTER.AUDIENCE.YES') },
            { id: 'false', name: t('CONTACTS_FILTER.AUDIENCE.NO') },
          ],
          filterOperators: pick(['equal_to']),
        }
      ),
      commerce(
        'commerce_order_status',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.ORDER_STATUS'),
        {
          inputType: 'multiSelect',
          options: optionsOf(ORDER_STATUSES, 'ORDER_STATUS'),
          filterOperators: equalityOperators.value,
        }
      ),
      commerce(
        'commerce_payment_status',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.PAYMENT_STATUS'),
        {
          inputType: 'multiSelect',
          options: optionsOf(PAYMENT_STATUSES, 'PAYMENT_STATUS'),
          filterOperators: equalityOperators.value,
        }
      ),
      commerce(
        'commerce_shipment_status',
        t('CONTACTS_FILTER.AUDIENCE.FIELDS.SHIPMENT_STATUS'),
        {
          inputType: 'multiSelect',
          options: optionsOf(SHIPMENT_STATUSES, 'SHIPMENT_STATUS'),
          filterOperators: equalityOperators.value,
        }
      ),
    ];
  });

  const audienceFilterTypes = computed(() => [
    ...conversationTypes.value,
    ...commerceTypes.value,
  ]);

  const unreadContacts = computed(() =>
    commerceFields.value?.accountId === accountId.value
      ? commerceFields.value.unread_contacts
      : 0
  );

  return { audienceFilterTypes, loadAudienceFields, unreadContacts };
}

/**
 * A saved condition's values, back in the shape its row's input edits.
 * @param {Object} filterType - The field's FilterType.
 * @param {Array} values - The saved values.
 */
export const audienceValuesForEdit = (filterType, values) => {
  const saved = (values || []).map(String);
  const matching = (filterType.options || []).filter(option =>
    saved.includes(String(option.id))
  );
  if (filterType.inputType === 'multiSelect') return matching;
  if (filterType.inputType === 'searchSelect') return matching[0] || {};
  return saved[0] ?? '';
};
