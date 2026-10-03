// Every catalogue, against the English strings the gallery and the wizard render. A recipe whose name, description,
// input label or requirement reason is missing would show a raw key, so it is a failure here rather than in the UI.
import recipes from 'dashboard/i18n/locale/en/recipes.json';
import automation from 'dashboard/i18n/locale/en/automation.json';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import { AUDIENCE_PRESETS } from '../audiencePresets';
import { AUTOMATION_RECIPES } from '../automationRecipes';
import { FLOW_TEMPLATES } from '../flowTemplates';
import { CATEGORIES, INPUT_TYPES, REQUIREMENTS } from '../index';
import { LANGUAGES } from '../starterCopy';

const CATALOGUES = {
  audience: AUDIENCE_PRESETS,
  automation: AUTOMATION_RECIPES,
  flow: FLOW_TEMPLATES,
};
const ALL = Object.values(CATALOGUES).flat();

const lookup = key =>
  key
    .split('.')
    .reduce((node, part) => (node === undefined ? undefined : node[part]), {
      ...recipes,
      ...automation,
      ...conversation,
    });

describe('recipe catalogues', () => {
  it('has a name and a description string for every recipe', () => {
    ALL.forEach(recipe => {
      expect(lookup(recipe.name), recipe.name).toBeTruthy();
      expect(lookup(recipe.description), recipe.description).toBeTruthy();
    });
  });

  it('has a label string for every input every recipe asks for', () => {
    ALL.forEach(recipe =>
      recipe.inputs.forEach(input => {
        const key = `RECIPES.INPUTS.${input.key.toUpperCase()}`;
        expect(lookup(key), `${recipe.id}: ${key}`).toBeTruthy();
      })
    );
  });

  it('has a reason string for every requirement any recipe declares', () => {
    const used = new Set(ALL.flatMap(recipe => recipe.requires));
    used.forEach(requirement => {
      const key = `RECIPES.REQUIREMENTS.${requirement.toUpperCase()}`;
      expect(lookup(key), key).toBeTruthy();
    });
  });

  it('has a label for every option the wizard can offer', () => {
    LANGUAGES.forEach(language =>
      expect(lookup(`RECIPES.LANGUAGES.${language.toUpperCase()}`)).toBeTruthy()
    );
    ['low', 'medium', 'high', 'urgent'].forEach(priority =>
      expect(
        lookup(`CONVERSATION.PRIORITY.OPTIONS.${priority.toUpperCase()}`)
      ).toBeTruthy()
    );
    [
      'commerce_order_created',
      'commerce_order_updated',
      'commerce_order_paid',
      'commerce_order_shipped',
      'commerce_order_delivered',
      'commerce_order_cancelled',
      'commerce_order_refunded',
    ].forEach(event =>
      expect(
        lookup(`AUTOMATION.EVENTS.${event.toUpperCase()}`),
        event
      ).toBeTruthy()
    );
  });

  it('has the gallery, wizard and error strings the dialog renders', () => {
    [
      'RECIPES.USE',
      'RECIPES.CREATE',
      'RECIPES.BACK',
      'RECIPES.FROM_SCRATCH',
      'RECIPES.REQUIRES',
      'RECIPES.NO_INPUTS',
      'RECIPES.CREATED',
      'RECIPES.CREATE_ERROR',
      'RECIPES.ERRORS.REQUIRED',
      'RECIPES.ERRORS.OUT_OF_RANGE',
      'RECIPES.ERRORS.INVALID_URL',
      'RECIPES.INPUTS.CHOOSE',
      'RECIPES.INPUTS.OPTIONAL',
      'RECIPES.INPUTS.NO_LABELS',
      'RECIPES.INPUTS.URL_PLACEHOLDER',
      'RECIPES.AUDIENCE.TITLE',
      'RECIPES.AUDIENCE.DESCRIPTION',
      'RECIPES.AUTOMATION.TITLE',
      'RECIPES.AUTOMATION.DESCRIPTION',
      'RECIPES.AUTOMATION.PROVENANCE',
      'RECIPES.FLOW.TITLE',
      'RECIPES.FLOW.DESCRIPTION',
      'RECIPES.FLOW.PROVENANCE',
    ].forEach(key => expect(lookup(key), key).toBeTruthy());
  });

  it('keeps every recipe in a category the product uses', () => {
    const known = Object.values(CATEGORIES);
    ALL.forEach(recipe => expect(known, recipe.id).toContain(recipe.category));
  });

  it('declares only requirements and input types the shared contract knows', () => {
    ALL.forEach(recipe => {
      recipe.requires.forEach(requirement =>
        expect(Object.values(REQUIREMENTS), recipe.id).toContain(requirement)
      );
      recipe.inputs.forEach(input =>
        expect(Object.values(INPUT_TYPES), recipe.id).toContain(input.type)
      );
    });
  });

  it('has the sizes the phase set out to deliver', () => {
    expect(AUDIENCE_PRESETS).toHaveLength(7);
    expect(AUTOMATION_RECIPES).toHaveLength(7);
    expect(FLOW_TEMPLATES).toHaveLength(6);
  });

  it('types every recipe as the catalogue it belongs to', () => {
    Object.entries(CATALOGUES).forEach(([type, catalogue]) =>
      catalogue.forEach(recipe => expect(recipe.type, recipe.id).toBe(type))
    );
  });

  it('uses ids that are unique across all three catalogues', () => {
    const ids = ALL.map(recipe => `${recipe.type}:${recipe.id}`);
    expect(new Set(ids).size).toBe(ids.length);
  });
});
