import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import contact from 'dashboard/i18n/locale/en/contact.json';
import contactFilters from 'dashboard/i18n/locale/en/contactFilters.json';
import campaign from 'dashboard/i18n/locale/en/campaign.json';
import recipes from 'dashboard/i18n/locale/en/recipes.json';
import AudiencesIndex from '../AudiencesIndex.vue';

const audiences = ref([]);
const uiFlags = ref({
  isFetching: false,
  isCreating: false,
  isDeleting: false,
});
const dispatch = vi.fn(() => Promise.resolve({ data: { id: 1 } }));
const push = vi.fn();
const filterRequest = vi.fn(() =>
  Promise.resolve({ data: { meta: { count: 412 } } })
);
const alerts = [];

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => {
    if (getter === 'customViews/getContactCustomViews') return audiences;
    if (getter === 'customViews/getUIFlags') return uiFlags;
    return ref(1);
  },
}));
vi.mock('dashboard/composables', () => ({
  useAlert: message => alerts.push(message),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(true) }),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({
    checkPermissions: () => true,
    checkInstallationType: () => true,
    isFeatureFlagEnabled: () => true,
  }),
}));
vi.mock('vue-router', () => ({
  useRouter: () => ({ push, resolve: () => ({ meta: {} }) }),
}));
vi.mock('dashboard/api/contacts', () => ({
  default: { filter: (...args) => filterRequest(...args) },
}));
vi.mock('dashboard/components-next/filter/contactProvider', () => ({
  useContactFilterContext: () => ({
    filterTypes: ref([
      {
        attributeKey: 'country_code',
        attributeName: 'Country',
        filterOperators: [{ value: 'equal_to', label: 'is' }],
        options: [{ id: 'KW', name: 'Kuwait' }],
      },
    ]),
  }),
}));
vi.mock('dashboard/components-next/filter/audienceProvider', () => ({
  useAudienceFilterTypes: () => ({
    audienceFilterTypes: ref([]),
    loadAudienceFields: vi.fn(() => Promise.resolve()),
  }),
}));

const AUDIENCE = {
  id: 7,
  name: 'VIP buyers',
  shared: true,
  query: {
    payload: [
      {
        attribute_key: 'country_code',
        filter_operator: 'equal_to',
        values: ['KW'],
      },
    ],
  },
};

const dialogStub = methods => ({
  template: '<div />',
  setup: (_props, { expose }) => {
    expose({
      dialogRef: { open: vi.fn(), close: vi.fn() },
      ...Object.fromEntries(methods.map(name => [name, vi.fn()])),
    });
    return () => null;
  },
});

const mountPage = () =>
  mount(AudiencesIndex, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: {
            en: { ...contact, ...contactFilters, ...campaign, ...recipes },
          },
        }),
      ],
      stubs: {
        Icon: true,
        EmojiIcon: true,
        Avatar: true,
        Spinner: true,
        // Stubbed, but with the methods the page calls on them: these dialogs expose `open`/`close` (and
        // `dialogRef`), and a bare stub would make the page look broken when it is not.
        RecipeDialog: dialogStub(['open', 'close']),
        CreateSegmentDialog: dialogStub(['open']),
        DeleteSegmentDialog: dialogStub([]),
      },
      directives: { onClickaway: {}, tooltip: {} },
    },
  });

describe('AudiencesIndex', () => {
  beforeEach(() => {
    audiences.value = [];
    uiFlags.value = { isFetching: false, isCreating: false, isDeleting: false };
    dispatch.mockClear();
    push.mockClear();
    filterRequest.mockClear();
    alerts.length = 0;
  });

  it('explains what an audience is, on the page that is about audiences', () => {
    expect(
      mountPage().find('[data-test-id="audience-explainer"]').exists()
    ).toBe(true);
  });

  it('reads the account’s audiences, because this page can be the first thing a session opens', () => {
    mountPage();

    expect(dispatch).toHaveBeenCalledWith('customViews/get', 'contact');
  });

  it('offers both ways in when there are none, rather than only a sentence', () => {
    const text = mountPage().text();

    expect(text).toContain('No audiences yet');
    expect(text).toContain('Start from a preset');
    expect(text).toContain('Build from filters');
  });

  it('lists each audience with the conditions it asks for', () => {
    audiences.value = [AUDIENCE];
    const wrapper = mountPage();

    expect(wrapper.findAll('[data-test-id="audience-card"]')).toHaveLength(1);
    expect(wrapper.text()).toContain('VIP buyers');
    expect(wrapper.text()).toContain('Country is Kuwait');
  });

  it('puts the account’s shared audiences above personal ones, then sorts by name', () => {
    audiences.value = [
      { ...AUDIENCE, id: 1, name: 'Zebra', shared: false },
      { ...AUDIENCE, id: 2, name: 'Beta', shared: true },
      { ...AUDIENCE, id: 3, name: 'Alpha', shared: false },
    ];
    const names = mountPage()
      .findAll('[data-test-id="audience-card"]')
      .map(card => card.text().split('\n')[0].trim());

    expect(names[0]).toContain('Beta');
    expect(names[1]).toContain('Alpha');
    expect(names[2]).toContain('Zebra');
  });

  it('evaluates no filter while the list is merely being read', () => {
    audiences.value = [AUDIENCE, { ...AUDIENCE, id: 8, name: 'Lapsed' }];
    mountPage();

    expect(filterRequest).not.toHaveBeenCalled();
  });

  it('counts an audience only when asked, and keeps the number on its card', async () => {
    audiences.value = [AUDIENCE];
    const wrapper = mountPage();
    const countButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('Count contacts now'));
    await countButton.trigger('click');
    await flushPromises();

    expect(filterRequest).toHaveBeenCalledWith(1, 'name', AUDIENCE.query);
    expect(wrapper.find('[data-test-id="audience-count"]').text()).toContain(
      '412 contacts'
    );
  });

  it('says so when a filter cannot be counted, instead of showing a zero', async () => {
    filterRequest.mockImplementationOnce(() =>
      Promise.reject(new Error('422'))
    );
    audiences.value = [AUDIENCE];
    const wrapper = mountPage();
    const countButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('Count contacts now'));
    await countButton.trigger('click');
    await flushPromises();

    expect(alerts).toContain(
      'Couldn’t count this audience. Open it to see why.'
    );
    expect(wrapper.find('[data-test-id="audience-count"]').exists()).toBe(
      false
    );
  });

  it('sends "build from filters" to the contacts list, where conditions are chosen by hand', async () => {
    const wrapper = mountPage();
    const button = wrapper
      .findAll('button')
      .find(item => item.text().includes('Build from filters'));
    await button.trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'contacts_dashboard_index',
      query: { page: 1 },
    });
  });
});
