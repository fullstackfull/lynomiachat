import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import recipes from 'dashboard/i18n/locale/en/recipes.json';
import conversation from 'dashboard/i18n/locale/en/conversation.json';
import automation from 'dashboard/i18n/locale/en/automation.json';
import RecipeInputs from '../RecipeInputs.vue';
import { INPUT_TYPES } from 'dashboard/recipes';

const CONTEXT = {
  teams: [{ id: 1, name: 'Orders' }],
  labels: [{ title: 'escalated' }],
  audiences: [{ id: 3, name: 'Recent buyers' }],
  stores: [{ id: 5, name: 'Main store' }],
  currencies: ['KWD'],
  whatsAppInboxes: [],
};

const mountInputs = inputs =>
  mount(RecipeInputs, {
    props: { modelValue: {}, inputs, context: CONTEXT, errors: {} },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...recipes, ...conversation, ...automation } },
        }),
      ],
      stubs: { Icon: true },
      directives: { onClickaway: {}, tooltip: {} },
    },
    attachTo: document.body,
  });

describe('RecipeInputs', () => {
  // The guard that matters: anything this component does not recognise falls through to its URL field, so an input
  // type the contract declares but the wizard cannot render silently offers a URL box for a team or a label. That is
  // how `label` shipped. Any new INPUT_TYPES entry has to be rendered here or removed from the contract.
  it('renders every input type the shared contract declares', () => {
    Object.entries(INPUT_TYPES).forEach(([name, type]) => {
      const wrapper = mountInputs([{ key: 'thing', type, required: true }]);
      const urlField = wrapper.find('input[type="url"]');

      if (type === INPUT_TYPES.URL) {
        expect(urlField.exists(), name).toBe(true);
        return;
      }
      expect(urlField.exists(), `${name} falls through to the URL field`).toBe(
        false
      );
    });
  });

  it('offers the account’s own teams, never an id to type in', () => {
    const wrapper = mountInputs([
      { key: 'team', type: INPUT_TYPES.TEAM, required: true },
    ]);

    expect(wrapper.text()).toContain('Orders');
  });

  it('offers labels by title, which is what every label action stores', () => {
    const wrapper = mountInputs([
      { key: 'labels', type: INPUT_TYPES.LABELS, required: true },
    ]);

    expect(wrapper.text()).toContain('escalated');
  });

  it('marks an optional input as optional, so a blank one is not read as unfinished', () => {
    const wrapper = mountInputs([
      { key: 'labels', type: INPUT_TYPES.LABELS, required: false },
    ]);

    expect(wrapper.text()).toContain('optional');
  });
});
