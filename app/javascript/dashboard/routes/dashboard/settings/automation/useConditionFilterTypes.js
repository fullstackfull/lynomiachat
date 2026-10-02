import { computed, h, toValue } from 'vue';
import { useI18n } from 'vue-i18n';
import { useOperators } from 'dashboard/components-next/filter/operators';
import { getAttributes } from 'dashboard/helper/automationHelper';
import { getAttributeIcon } from 'dashboard/components-next/filter/helper/filterAttributeIcons';

const INPUT_TYPE_MAP = {
  multi_select: 'multiSelect',
  search_select: 'searchSelect',
  plain_text: 'plainText',
  multi_text: 'multiText',
  date: 'date',
};

// The condition fields of an automation event as the filter ConditionRow takes them: the rule builder's conditions,
// and a Lynomia flow's Condition nodes (docs/flow-builder/04-node-contracts.md §conditions), which hold the same
// Automation conditions.
export function useConditionFilterTypes(
  automationTypes,
  eventName,
  getConditionDropdownValues
) {
  const { t } = useI18n();
  const { operators } = useOperators();

  const translatedAttributes = (types, event) =>
    getAttributes(types, event).map(attribute => {
      const skipTranslation =
        attribute.translated ||
        attribute.customAttributeType ||
        ['contact_custom_attribute', 'conversation_custom_attribute'].includes(
          attribute.key
        );
      return {
        ...attribute,
        name: skipTranslation
          ? attribute.name
          : t(`AUTOMATION.ATTRIBUTES.${attribute.name}`),
      };
    });

  const filterOperatorsOf = attr =>
    (attr.filterOperators || []).map(op => {
      const enriched = operators.value[op.value];
      // Lynomia's audience condition reads "is in / is not in" on the same operators.
      if (enriched && op.lynomiaLabel) {
        return { ...enriched, label: op.lynomiaLabel };
      }
      if (enriched) return enriched;
      return {
        value: op.value,
        label: t(`FILTER.OPERATOR_LABELS.${op.value}`),
        hasInput: true,
        inputOverride: null,
        icon: h('span', { class: 'i-ph-equals-bold !text-n-blue-11' }),
      };
    });

  return computed(() => {
    const types = toValue(automationTypes);
    const event = toValue(eventName);
    if (!event || !types[event]) return [];

    return translatedAttributes(types, event).map(attr => {
      if (attr.disabled) {
        return { value: attr.key, label: attr.name, disabled: true };
      }

      return {
        attributeKey: attr.key,
        value: attr.key,
        attributeName: attr.name,
        label: attr.name,
        icon: getAttributeIcon({
          attributeKey: attr.key,
          attributeDisplayType: attr.attributeDisplayType,
        }),
        inputType: INPUT_TYPE_MAP[attr.inputType] || 'plainText',
        options: getConditionDropdownValues(attr.key) || [],
        filterOperators: filterOperatorsOf(attr),
        dataType: 'text',
        attributeModel: attr.customAttributeType || 'standard',
      };
    });
  });
}
