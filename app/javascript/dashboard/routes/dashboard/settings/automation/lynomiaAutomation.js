import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAudienceFilterTypes } from 'dashboard/components-next/filter/audienceProvider';
import { AUTOMATIONS } from './constants';

// Lynomia Automation in Chatwoot's rule builder (docs/automation/03, 04): Commerce triggers, and Audience and Commerce
// condition groups appended to every trigger's conditions, like the custom attribute groups. The fields reuse the
// Audience builder's (audienceProvider.js); only shared audiences are offered.

export const COMMERCE_EVENTS = [
  'commerce_order_created',
  'commerce_order_updated',
  'commerce_order_paid',
  'commerce_order_shipped',
  'commerce_order_delivered',
  'commerce_order_cancelled',
  'commerce_order_refunded',
];

// A store event is not a customer message: these actions are not offered on Commerce triggers.
export const CUSTOMER_MESSAGE_ACTIONS = ['send_message', 'send_attachment'];

export const isCommerceEvent = event => COMMERCE_EVENTS.includes(event);

const AUTOMATION_INPUT_TYPES = {
  multiSelect: 'multi_select',
  searchSelect: 'search_select',
  date: 'date',
};
const EQUALITY = [{ value: 'equal_to' }, { value: 'not_equal_to' }];

export function useLynomiaAutomation() {
  const { t } = useI18n();
  const store = useStore();
  const { isCloudFeatureEnabled } = useAccount();
  const contactViews = useMapGetter('customViews/getContactCustomViews');
  const { audienceFilterTypes, loadAudienceFields } = useAudienceFilterTypes();

  const isCommerceEnabled = computed(() =>
    isCloudFeatureEnabled(FEATURE_FLAGS.LYNOMIA_COMMERCE)
  );
  const sharedAudiences = computed(() =>
    (contactViews.value || [])
      .filter(view => view.shared)
      .map(({ id, name }) => ({ id, name }))
  );
  const commerceTypes = computed(() =>
    audienceFilterTypes.value.filter(type => type.attributeModel === 'commerce')
  );
  const optionsOf = key =>
    commerceTypes.value.find(type => type.attributeKey === key)?.options;

  const load = () =>
    Promise.all([
      store.dispatch('customViews/get', 'contact'),
      loadAudienceFields(),
    ]);

  const events = computed(() =>
    isCommerceEnabled.value
      ? COMMERCE_EVENTS.map(key => ({
          key,
          value: t(`AUTOMATION.EVENTS.${key.toUpperCase()}`),
          group: t('AUTOMATION.LYNOMIA.GROUPS.COMMERCE_TRIGGERS'),
        }))
      : []
  );

  const header = (key, name) => ({
    key,
    name,
    disabled: true,
    translated: true,
    lynomia: true,
  });
  const entry = (key, name, inputType, filterOperators) => ({
    key,
    name,
    inputType,
    filterOperators,
    translated: true,
    lynomia: true,
  });

  const conditionTypes = event => {
    const list = [
      header(
        'lynomia_audience_header',
        t('AUTOMATION.LYNOMIA.GROUPS.AUDIENCE')
      ),
      entry(
        'contact_audience',
        t('AUTOMATION.LYNOMIA.CONTACT_AUDIENCE'),
        'multi_select',
        [
          { value: 'equal_to', lynomiaLabel: t('AUTOMATION.LYNOMIA.IS_IN') },
          {
            value: 'not_equal_to',
            lynomiaLabel: t('AUTOMATION.LYNOMIA.IS_NOT_IN'),
          },
        ]
      ),
    ];
    if (!isCommerceEnabled.value) return list;

    list.push(
      header('lynomia_commerce_header', t('AUTOMATION.LYNOMIA.GROUPS.COMMERCE'))
    );
    if (isCommerceEvent(event)) {
      list.push(
        entry(
          'commerce_event_store',
          t('AUTOMATION.LYNOMIA.EVENT_STORE'),
          'multi_select',
          EQUALITY
        ),
        entry(
          'commerce_event_provider',
          t('AUTOMATION.LYNOMIA.EVENT_PROVIDER'),
          'multi_select',
          EQUALITY
        )
      );
    }
    commerceTypes.value.forEach(type =>
      list.push(
        entry(
          type.attributeKey,
          type.attributeName,
          AUTOMATION_INPUT_TYPES[type.inputType] || 'plain_text',
          type.filterOperators.map(operator => ({ value: operator.value }))
        )
      )
    );
    return list;
  };

  /**
   * Adds Commerce triggers (with the conversation conditions: their rules act on the contact's latest conversation)
   * and appends the Audience and Commerce groups to every trigger. Safe to call again once options load.
   * @param {Object} automationTypes - The reactive automation types of useAutomation.
   */
  const manifest = automationTypes => {
    if (isCommerceEnabled.value) {
      const base = (
        automationTypes.conversation_updated || AUTOMATIONS.conversation_updated
      ).conditions.filter(condition => !condition.lynomia);
      COMMERCE_EVENTS.forEach(event => {
        automationTypes[event] = { conditions: [...base] };
      });
    }
    Object.keys(automationTypes).forEach(event => {
      automationTypes[event].conditions = [
        ...automationTypes[event].conditions.filter(
          condition => !condition.lynomia
        ),
        ...conditionTypes(event),
      ];
    });
  };

  const conditionOptions = key => {
    if (key === 'contact_audience') return sharedAudiences.value;
    if (key === 'commerce_event_store') return optionsOf('commerce_store');
    if (key === 'commerce_event_provider')
      return optionsOf('commerce_provider');
    return optionsOf(key);
  };

  const actionAllowed = (event, actionKey) =>
    !(isCommerceEvent(event) && CUSTOMER_MESSAGE_ACTIONS.includes(actionKey));

  return {
    load,
    events,
    manifest,
    conditionOptions,
    actionAllowed,
    isCommerceEnabled,
  };
}
