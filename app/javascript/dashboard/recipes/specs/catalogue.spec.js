// Every catalogue, against the strings the gallery and the wizard render — in **both** locales the gallery ships.
// A recipe whose name, description, input label or requirement reason is missing would show a raw key, so it is a
// failure here rather than in the UI, and a new entry cannot be added in English only.
import recipes from 'dashboard/i18n/locale/en/recipes.json';
import automation from 'dashboard/i18n/locale/en/automation.json';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import recipesAr from 'dashboard/i18n/locale/ar/recipes.json';
import automationAr from 'dashboard/i18n/locale/ar/automation.json';
import conversationAr from 'dashboard/i18n/locale/ar/conversation.json';
import { AUDIENCE_PRESETS } from '../audiencePresets';
import { AUTOMATION_RECIPES } from '../automationRecipes';
import { FLOW_TEMPLATES } from '../flowTemplates';
import { MACRO_STARTERS } from '../macroStarters';
import { SETUP_RECIPES } from '../setupRecipes';
import { CATEGORIES, INPUT_TYPES, REQUIREMENTS } from '../index';
import { LANGUAGES } from '../starterCopy';

const CATALOGUES = {
  audience: AUDIENCE_PRESETS,
  automation: AUTOMATION_RECIPES,
  flow: FLOW_TEMPLATES,
  macro: MACRO_STARTERS,
  setup: SETUP_RECIPES,
};
const ALL = Object.values(CATALOGUES).flat();

const MESSAGES = {
  en: { ...recipes, ...automation, ...conversation },
  ar: { ...recipesAr, ...automationAr, ...conversationAr },
};
const LOCALES = Object.keys(MESSAGES);

const lookupIn = (locale, key) =>
  key
    .split('.')
    .reduce(
      (node, part) => (node === undefined ? undefined : node[part]),
      MESSAGES[locale]
    );
const lookup = key => lookupIn('en', key);

describe('recipe catalogues', () => {
  it.each(LOCALES)(
    'has a name and a description string for every recipe (%s)',
    locale => {
      ALL.forEach(recipe => {
        expect(lookupIn(locale, recipe.name), recipe.name).toBeTruthy();
        expect(
          lookupIn(locale, recipe.description),
          recipe.description
        ).toBeTruthy();
      });
    }
  );

  it.each(LOCALES)(
    'has a name for every object a setup recipe creates (%s)',
    locale => {
      SETUP_RECIPES.forEach(recipe =>
        recipe.steps.forEach(step => {
          expect(lookupIn(locale, step.name), step.name).toBeTruthy();
          expect(
            lookupIn(locale, `RECIPES.SETUP.OBJECTS.${step.key.toUpperCase()}`),
            step.key
          ).toBeTruthy();
        })
      );
    }
  );

  it('creates only object kinds a setup recipe can actually create', () => {
    SETUP_RECIPES.forEach(recipe => {
      expect(recipe.steps.length).toBeGreaterThan(1);
      recipe.steps.forEach(step =>
        expect(['audience', 'automation'], step.key).toContain(step.type)
      );
      // Unique keys, because a later step reads earlier ones by key.
      const keys = recipe.steps.map(step => step.key);
      expect(new Set(keys).size).toBe(keys.length);
    });
  });

  it.each(LOCALES)(
    'has the platform note it claims, in both languages (%s)',
    locale => {
      ALL.filter(recipe => recipe.providerNote).forEach(recipe => {
        expect(
          lookupIn(locale, recipe.providerNote),
          recipe.providerNote
        ).toBeTruthy();
      });
    }
  );

  it('says which platforms report a trigger only some of them report', () => {
    // The four store platforms do not normalize the same order statuses: WooCommerce has no shipped status and
    // Shopify no cancelled one, so a starter built on either must say so rather than read as ready everywhere.
    [
      'commerce_order_shipped_label',
      'commerce_order_cancelled_followup',
    ].forEach(id => {
      const recipe = ALL.find(item => item.id === id);
      expect(recipe.providerNote, id).toBeTruthy();
    });
  });

  it.each(LOCALES)(
    'has a label string for every input every recipe asks for (%s)',
    locale => {
      ALL.forEach(recipe =>
        recipe.inputs.forEach(input => {
          const key = `RECIPES.INPUTS.${input.key.toUpperCase()}`;
          expect(lookupIn(locale, key), `${recipe.id}: ${key}`).toBeTruthy();
        })
      );
    }
  );

  it.each(LOCALES)(
    'has a reason string for every requirement any recipe declares (%s)',
    locale => {
      const used = new Set(ALL.flatMap(recipe => recipe.requires));
      used.forEach(requirement => {
        const key = `RECIPES.REQUIREMENTS.${requirement.toUpperCase()}`;
        expect(lookupIn(locale, key), `${locale}: ${key}`).toBeTruthy();
      });
    }
  );

  it('keeps the two recipe locales structurally identical', () => {
    const leaves = node =>
      Object.entries(node)
        .flatMap(([key, value]) =>
          value && typeof value === 'object'
            ? leaves(value).map(child => `${key}.${child}`)
            : [key]
        )
        .sort();

    expect(leaves(recipesAr)).toEqual(leaves(recipes));
  });

  it('keeps every interpolation placeholder in the Arabic strings', () => {
    const placeholders = text =>
      typeof text === 'string' ? (text.match(/\{\w+\}/g) ?? []).sort() : [];
    const walk = (english, arabic, path = '') => {
      if (english && typeof english === 'object') {
        Object.keys(english).forEach(key =>
          walk(english[key], arabic?.[key], path ? `${path}.${key}` : key)
        );
        return;
      }
      expect(placeholders(arabic), path).toEqual(placeholders(english));
    };

    walk(recipes, recipesAr);
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

  // Not a target, a tripwire: a catalogue that changes size should change this line too, deliberately.
  it('ships the catalogue sizes it says it does', () => {
    expect(AUDIENCE_PRESETS).toHaveLength(9);
    expect(AUTOMATION_RECIPES).toHaveLength(12);
    expect(FLOW_TEMPLATES).toHaveLength(8);
    expect(MACRO_STARTERS).toHaveLength(6);
    expect(SETUP_RECIPES).toHaveLength(1);
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
