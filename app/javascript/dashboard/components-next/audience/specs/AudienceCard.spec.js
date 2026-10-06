import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import contact from 'dashboard/i18n/locale/en/contact.json';
import contactFilters from 'dashboard/i18n/locale/en/contactFilters.json';
import campaign from 'dashboard/i18n/locale/en/campaign.json';
import AudienceCard from '../AudienceCard.vue';

const permissions = ref(['administrator']);
const isAdmin = ref(true);

vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    checkPermissions: required =>
      !required?.length ||
      required.some(permission => permissions.value.includes(permission)),
    checkInstallationType: () => true,
    isFeatureFlagEnabled: () => true,
  }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(1),
}));

// The cross-module actions ask the target route for its own feature flag and permissions, so the routes they name
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

const FILTER_TYPES = [
  {
    attributeKey: 'country_code',
    attributeName: 'Country',
    filterOperators: [{ value: 'equal_to', label: 'is' }],
    options: [{ id: 'KW', name: 'Kuwait' }],
  },
  {
    attributeKey: 'commerce_orders_count',
    attributeName: 'Orders',
    filterOperators: [{ value: 'is_greater_than', label: 'is greater than' }],
  },
];

const SHARED = {
  id: 7,
  name: 'VIP buyers',
  shared: true,
  active_automation_rules_count: 2,
  campaigns_count: 1,
  query: {
    payload: [
      {
        attribute_key: 'country_code',
        filter_operator: 'equal_to',
        values: ['KW'],
        query_operator: 'and',
      },
      {
        attribute_key: 'commerce_orders_count',
        filter_operator: 'is_greater_than',
        values: [2],
      },
    ],
  },
};

const PERSONAL = {
  id: 9,
  name: 'My drafts',
  shared: false,
  query: { payload: [] },
};

const mountCard = (props = {}) =>
  mount(AudienceCard, {
    props: { audience: SHARED, filterTypes: FILTER_TYPES, ...props },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...contact, ...contactFilters, ...campaign } },
        }),
      ],
      stubs: { Icon: true, EmojiIcon: true, Avatar: true, Spinner: true },
      directives: { onClickaway: {}, tooltip: {} },
    },
  });

const openMenu = async wrapper => {
  await wrapper.find('button[aria-label^="More actions"]').trigger('click');
  return wrapper;
};

describe('AudienceCard', () => {
  beforeEach(() => {
    permissions.value = ['administrator'];
    isAdmin.value = true;
  });

  it('says what the audience actually asks for, read from its stored conditions', () => {
    const text = mountCard().text();

    expect(text).toContain('VIP buyers');
    expect(text).toContain('Country is Kuwait');
    expect(text).toContain('Orders is greater than 2');
  });

  it('marks a shared audience as the account’s and a personal one as the user’s own', () => {
    expect(mountCard().text()).toContain('Shared');
    expect(mountCard({ audience: PERSONAL }).text()).toContain('Only you');
  });

  it('says an audience with no conditions matches everyone, rather than showing a blank line', () => {
    expect(mountCard({ audience: PERSONAL }).text()).toContain(
      'No conditions saved'
    );
  });

  it('shows what depends on the audience, which is what stops it being deleted', () => {
    const text = mountCard().text();

    expect(text).toContain('2 automation rules');
    expect(text).toContain('1 campaign');
  });

  it('says nothing about usage for an audience nothing uses', () => {
    expect(mountCard({ audience: PERSONAL }).text()).not.toContain('Used by');
  });

  it('offers the count as an action and evaluates nothing on its own', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain('Count contacts now');
    expect(wrapper.find('[data-test-id="audience-count"]').exists()).toBe(
      false
    );
  });

  it('shows the count once it has been asked for', () => {
    const wrapper = mountCard({ count: 412 });

    expect(wrapper.find('[data-test-id="audience-count"]').text()).toContain(
      '412 contacts'
    );
    expect(wrapper.text()).not.toContain('Count contacts now');
  });

  it('asks the page for a count when the action is used', async () => {
    const wrapper = mountCard();
    const countButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('Count contacts now'));
    await countButton.trigger('click');

    expect(wrapper.emitted('count')).toHaveLength(1);
  });

  it('offers the cross-module actions for a shared audience', async () => {
    const wrapper = await openMenu(mountCard());

    expect(wrapper.text()).toContain('Use in a new automation rule');
    expect(wrapper.text()).toContain('Use in a new WhatsApp campaign');
  });

  it('offers neither cross-module action for a personal audience, because neither can reference one', async () => {
    const wrapper = await openMenu(mountCard({ audience: PERSONAL }));

    expect(wrapper.text()).not.toContain('Use in a new automation rule');
    expect(wrapper.text()).not.toContain('Use in a new WhatsApp campaign');
  });

  it('does not offer a page the page itself would refuse', async () => {
    permissions.value = ['agent'];
    const wrapper = await openMenu(mountCard());

    expect(wrapper.text()).not.toContain('Use in a new automation rule');
    expect(wrapper.text()).not.toContain('Use in a new WhatsApp campaign');
  });

  it('lets an administrator edit and delete a shared audience', async () => {
    const wrapper = await openMenu(mountCard());

    expect(wrapper.text()).toContain('Edit its conditions');
    expect(wrapper.text()).toContain('Delete this audience');
  });

  it('offers neither edit nor delete on a shared audience to someone who is not an administrator', async () => {
    isAdmin.value = false;
    const wrapper = await openMenu(mountCard());

    expect(wrapper.text()).not.toContain('Edit its conditions');
    expect(wrapper.text()).not.toContain('Delete this audience');
    // Still readable, still duplicable: those the server allows.
    expect(wrapper.text()).toContain('Open this audience');
    expect(wrapper.text()).toContain('Duplicate this audience');
  });

  it('lets a non-administrator manage their own personal audience', async () => {
    isAdmin.value = false;
    const wrapper = await openMenu(mountCard({ audience: PERSONAL }));

    expect(wrapper.text()).toContain('Edit its conditions');
    expect(wrapper.text()).toContain('Delete this audience');
  });

  it('reports each action as its own event, so the page never receives an unknown one', async () => {
    const wrapper = await openMenu(mountCard());
    const items = wrapper.findAll('[role="menuitem"], li button, button');
    const edit = items.find(item =>
      item.text().includes('Edit its conditions')
    );
    await edit.trigger('click');

    expect(wrapper.emitted('edit')).toHaveLength(1);
  });

  it('names the audience in the menu’s accessible name, so two cards are told apart', () => {
    const wrapper = mountCard();

    expect(
      wrapper
        .find('button[aria-label^="More actions"]')
        .attributes('aria-label')
    ).toBe('More actions for VIP buyers');
  });
});
