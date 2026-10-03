import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import contact from 'dashboard/i18n/locale/en/contact.json';
import ContactMoreActions from '../ContactMoreActions.vue';

const permissions = ref(['administrator']);
const featureFlags = ref(true);

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    checkPermissions: required =>
      !required?.length ||
      required.some(permission => permissions.value.includes(permission)),
    checkInstallationType: () => true,
    isFeatureFlagEnabled: () => featureFlags.value,
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(1),
}));

// The two cross-module actions ask the target route for its own feature flag and permissions, so the routes they name
// must resolve with that meta.
const ROUTES = {
  automation_list: {
    meta: { featureFlag: 'automations', permissions: ['administrator'] },
  },
  campaigns_whatsapp_index: {
    meta: { featureFlag: 'whatsapp_campaigns', permissions: ['administrator'] },
  },
};

vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: ({ name }) => ROUTES[name] || { meta: {} } }),
}));

const SHARED = {
  id: 7,
  name: 'VIP buyers',
  shared: true,
  active_automation_rules_count: 2,
  campaigns_count: 1,
};

const mountMenu = async segment => {
  const wrapper = mount(ContactMoreActions, {
    props: { segment },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: contact } }),
      ],
      stubs: { Icon: true, EmojiIcon: true, Avatar: true, Spinner: true },
      directives: { onClickaway: {}, tooltip: {} },
    },
  });
  await wrapper.find('[data-test-id="contact-more-actions"]').trigger('click');
  return wrapper;
};

describe('ContactMoreActions', () => {
  beforeEach(() => {
    permissions.value = ['administrator'];
    featureFlags.value = true;
  });

  it('offers only the preset shortcut, and the contact actions, when no audience is open', async () => {
    const wrapper = await mountMenu(null);

    expect(wrapper.text()).toContain('Add contact');
    expect(wrapper.text()).toContain('Import contacts');
    expect(wrapper.text()).toContain('New audience from a preset');
    expect(wrapper.text()).not.toContain('Use in a new automation rule');
    expect(wrapper.text()).not.toContain('Duplicate this audience');
    expect(wrapper.text()).not.toContain('Copy link to this audience');
  });

  it('offers the cross-module actions, the duplicate and the link for a shared audience', async () => {
    const wrapper = await mountMenu(SHARED);

    expect(wrapper.text()).toContain('Use in a new automation rule');
    expect(wrapper.text()).toContain('Use in a new WhatsApp campaign');
    expect(wrapper.text()).toContain('Duplicate this audience');
    expect(wrapper.text()).toContain('Copy link to this audience');
    expect(wrapper.text()).toContain('New audience from a preset');
    // Still the contact actions, below the audience ones.
    expect(wrapper.text()).toContain('Add contact');
  });

  it('says what already references the audience', async () => {
    const wrapper = await mountMenu(SHARED);

    expect(wrapper.text()).toContain('Used by 2 automation rules · 1 campaign');
  });

  it('says nothing about usage when nothing references it', async () => {
    const wrapper = await mountMenu({
      ...SHARED,
      active_automation_rules_count: 0,
      campaigns_count: 0,
    });

    expect(wrapper.text()).not.toContain('Used by');
  });

  it('withholds the cross-module actions for a personal audience, which neither module may reference', async () => {
    const wrapper = await mountMenu({
      id: 9,
      name: 'My drafts',
      shared: false,
    });

    expect(wrapper.text()).not.toContain('Use in a new automation rule');
    expect(wrapper.text()).not.toContain('Use in a new WhatsApp campaign');
    expect(wrapper.text()).toContain('Duplicate this audience');
    expect(wrapper.text()).toContain('Copy link to this audience');
  });

  it('withholds the cross-module actions from an agent, whose target routes refuse them', async () => {
    permissions.value = ['agent', 'contact_manage'];
    const wrapper = await mountMenu(SHARED);

    expect(wrapper.text()).not.toContain('Use in a new automation rule');
    expect(wrapper.text()).not.toContain('Use in a new WhatsApp campaign');
    expect(wrapper.text()).toContain('Copy link to this audience');
  });

  it('withholds a cross-module action when the target feature is off for the account', async () => {
    featureFlags.value = false;
    const wrapper = await mountMenu(SHARED);

    expect(wrapper.text()).not.toContain('Use in a new automation rule');
    expect(wrapper.text()).not.toContain('Use in a new WhatsApp campaign');
  });

  it('emits the action the chosen item names', async () => {
    const wrapper = await mountMenu(SHARED);
    const items = wrapper.findAll('button');
    const useInAutomation = items.find(item =>
      item.text().includes('Use in a new automation rule')
    );
    await useInAutomation.trigger('click');

    expect(wrapper.emitted('useInAutomation')).toHaveLength(1);
  });
});
