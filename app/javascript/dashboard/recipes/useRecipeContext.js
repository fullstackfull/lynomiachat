// What the account has, for deciding which recipes it can use and what the wizards may offer
// (docs/usability/10-recipe-architecture.md §availability). Every answer comes from data the dashboard already holds
// or from the one Commerce options call the audience filter already makes, so opening the gallery adds no request of
// its own and asks no provider anything. Deterministic: no model, no scoring, nothing sent anywhere.

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAudienceFilterTypes } from 'dashboard/components-next/filter/audienceProvider';
import { sharedAudiences } from 'dashboard/helper/audienceHelper';
import { REQUIREMENTS, RECIPE_STATUS } from './index';

export function useRecipeContext() {
  const { t } = useI18n();
  const { isCloudFeatureEnabled } = useAccount();
  const teams = useMapGetter('teams/getTeams');
  const labels = useMapGetter('labels/getLabels');
  const contactViews = useMapGetter('customViews/getContactCustomViews');
  const whatsAppInboxes = useMapGetter('inboxes/getWhatsAppInboxes');
  const { loadAudienceFields, commerceStores, commerceCurrencies } =
    useAudienceFilterTypes();

  const isCommerceEnabled = computed(() =>
    isCloudFeatureEnabled(FEATURE_FLAGS.LYNOMIA_COMMERCE)
  );

  const context = computed(() => ({
    teams: teams.value || [],
    labels: labels.value || [],
    audiences: sharedAudiences(contactViews.value),
    stores: commerceStores.value,
    currencies: commerceCurrencies.value,
    whatsAppInboxes: whatsAppInboxes.value || [],
  }));

  // One answer per requirement. A requirement that is not met is why a recipe reads "requires setup" instead of
  // offering a Create button, and the gallery says which one.
  const satisfied = computed(() => ({
    [REQUIREMENTS.CONTACT_FILTER]: isCloudFeatureEnabled(FEATURE_FLAGS.CRM),
    [REQUIREMENTS.COMMERCE]: isCommerceEnabled.value,
    [REQUIREMENTS.COMMERCE_STORE]: context.value.stores.length > 0,
    [REQUIREMENTS.COMMERCE_CURRENCY]: context.value.currencies.length > 0,
    [REQUIREMENTS.FLOW_BUILDER]: isCloudFeatureEnabled(
      FEATURE_FLAGS.LYNOMIA_FLOW_BUILDER
    ),
    [REQUIREMENTS.AUTOMATIONS]: isCloudFeatureEnabled(
      FEATURE_FLAGS.AUTOMATIONS
    ),
    [REQUIREMENTS.SHARED_AUDIENCE]: context.value.audiences.length > 0,
    [REQUIREMENTS.TEAM]: context.value.teams.length > 0,
    [REQUIREMENTS.LABEL]: context.value.labels.length > 0,
    [REQUIREMENTS.WEBHOOKS]: isCloudFeatureEnabled(
      FEATURE_FLAGS.API_AND_WEBHOOKS
    ),
  }));

  /**
   * A recipe with what this account makes of it.
   * @param {Object} recipe - A recipe from one of the catalogues.
   * @returns {Object} The recipe, plus its `status`, the `missing` requirement keys and their readable `reasons`.
   */
  const describe = recipe => {
    const missing = recipe.requires.filter(key => !satisfied.value[key]);
    return {
      ...recipe,
      status: missing.length
        ? RECIPE_STATUS.REQUIRES_SETUP
        : RECIPE_STATUS.AVAILABLE,
      missing,
      reasons: missing.map(key =>
        t(`RECIPES.REQUIREMENTS.${key.toUpperCase()}`)
      ),
    };
  };

  /**
   * A catalogue described for this account, with the recipes it can use first and, among those, the ones its own
   * setup makes most relevant. Commerce templates come first for an account with a connected store; audience-based
   * ones come first for an account that has shared audiences. Order only — nothing is hidden by relevance.
   * @param {Array} recipes - A catalogue.
   * @returns {Array} The described recipes, in the order to show them.
   */
  const describeAll = recipes => {
    const relevance = recipe => {
      if (
        recipe.requires.includes(REQUIREMENTS.COMMERCE) &&
        satisfied.value[REQUIREMENTS.COMMERCE_STORE]
      ) {
        return 0;
      }
      if (recipe.requires.includes(REQUIREMENTS.SHARED_AUDIENCE)) return 1;
      return 2;
    };

    return recipes
      .map(describe)
      .map((recipe, index) => ({ recipe, index }))
      .sort((a, b) => {
        const available =
          Number(a.recipe.status !== RECIPE_STATUS.AVAILABLE) -
          Number(b.recipe.status !== RECIPE_STATUS.AVAILABLE);
        if (available) return available;

        const byRelevance = relevance(a.recipe) - relevance(b.recipe);
        return byRelevance || a.index - b.index;
      })
      .map(({ recipe }) => recipe);
  };

  /**
   * Values the wizard can fill in without asking, because the account leaves no choice: exactly one team, one store,
   * one currency, one audience. Never a webhook URL, a threshold or anything destructive.
   * @param {Object} recipe - A described recipe.
   * @returns {Object} The values to start the form with.
   */
  const presetValues = recipe => {
    const sole = { team: 'teams', store: 'stores', audience: 'audiences' };
    return recipe.inputs.reduce((values, input) => {
      if (input.default !== undefined) values[input.key] = input.default;

      const list = sole[input.type] && context.value[sole[input.type]];
      if (list?.length === 1) values[input.key] = list[0].id;
      if (input.type === 'currency' && context.value.currencies.length === 1) {
        values[input.key] = context.value.currencies[0];
      }
      return values;
    }, {});
  };

  return {
    context,
    loadCommerceOptions: loadAudienceFields,
    describe,
    describeAll,
    presetValues,
  };
}
