import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import campaign from 'dashboard/i18n/locale/en/campaign.json';
import contactFilters from 'dashboard/i18n/locale/en/contactFilters.json';
import CampaignsAPI from 'dashboard/api/campaigns';
import CampaignRecipients from '../CampaignRecipients.vue';

// The debounce the preview waits out before it asks the server.
const PREVIEW_DELAY_MS = 300;

vi.mock('dashboard/api/campaigns', () => ({
  default: {
    audiencePreview: vi.fn(() => Promise.resolve({ data: { count: 0 } })),
  },
}));

// The two filter vocabularies the summary reads from. Stubbed so this spec is about the recipients section,
// not about the filter providers.
vi.mock('dashboard/components-next/filter/contactProvider', () => ({
  useContactFilterContext: () => ({
    filterTypes: {
      value: [
        {
          attributeKey: 'country_code',
          attributeName: 'Country',
          filterOperators: [{ value: 'equal_to', label: 'is' }],
          options: [{ id: 'KW', name: 'Kuwait' }],
        },
      ],
    },
  }),
}));
vi.mock('dashboard/components-next/filter/audienceProvider', () => ({
  useAudienceFilterTypes: () => ({ audienceFilterTypes: { value: [] } }),
}));

const en = { ...campaign, ...contactFilters };

const buildStore = ({ contactViews = [], isFetching = false } = {}) =>
  createStore({
    getters: {
      'labels/getLabels': () => [{ id: 1, title: 'vip' }],
      'customViews/getContactCustomViews': () => contactViews,
      'customViews/getUIFlags': () => ({ isFetching }),
    },
  });

const mountRecipients = (storeOptions = {}, props = {}) =>
  mount(CampaignRecipients, {
    props,
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en } }),
        buildStore(storeOptions),
      ],
      stubs: { TagMultiSelectComboBox: true, Icon: true },
    },
  });

const sharedAudience = {
  id: 9,
  name: 'Kuwait buyers',
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

describe('CampaignRecipients', () => {
  it('explains what a shared audience is when the account has none', () => {
    const wrapper = mountRecipients();

    expect(wrapper.find('[data-test-id="audience-explainer"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('What a shared audience is');
  });

  it('offers to create one and promises to keep the campaign, instead of sending the user away', () => {
    const wrapper = mountRecipients();

    const create = wrapper.find('[data-test-id="campaign-create-audience"]');
    expect(create.exists()).toBe(true);
    expect(wrapper.text()).toContain(
      'We will keep this campaign while you build one.'
    );
  });

  it('asks the page to start the round trip rather than navigating itself', async () => {
    const wrapper = mountRecipients();

    await wrapper
      .findComponent('[data-test-id="campaign-create-audience"]')
      .vm.$emit('click');

    expect(wrapper.emitted('createAudience')).toHaveLength(1);
  });

  it('does not claim the account has no audiences while they are still loading', () => {
    const wrapper = mountRecipients({ isFetching: true });

    expect(wrapper.find('[data-test-id="audience-explainer"]').exists()).toBe(
      false
    );
  });

  it('stops explaining once the account has an audience', () => {
    const wrapper = mountRecipients({ contactViews: [sharedAudience] });

    expect(wrapper.find('[data-test-id="audience-explainer"]').exists()).toBe(
      false
    );
  });

  it('describes each audience by its conditions, so the picker is not a list of bare names', () => {
    const wrapper = mountRecipients({ contactViews: [sharedAudience] });

    const options = wrapper
      .findComponent('[data-test-id="campaign-recipient-audiences"]')
      .props('options');

    expect(options).toEqual([
      { value: 9, label: 'Kuwait buyers', description: 'Country is Kuwait' },
    ]);
  });

  // THE PREVIEW. Both examples below pin behaviour the fix to this component changed and
  // nothing covered -- the gap an audit of the closure found rather than a run.
  describe('the count', () => {
    beforeEach(() => {
      CampaignsAPI.audiencePreview.mockClear();
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    // A form seeded from a draft does all of its seeding during setup -- coming back from
    // Contacts restores the inbox, the template and the audience before this component
    // mounts -- so no watched source ever changes afterwards. Without an immediate run the
    // request was never issued and the section read "Counting matching contacts…" for ever,
    // on the one journey where the merchant most wants the number.
    it('counts an audience that was already there when it mounted', async () => {
      mountRecipients({}, { labelIds: [1] });

      await vi.advanceTimersByTimeAsync(PREVIEW_DELAY_MS);

      expect(CampaignsAPI.audiencePreview).toHaveBeenCalledTimes(1);
    });

    // The count is nulled on every change precisely so a number computed for the previous
    // question is not left on screen. An in-flight answer to that question undoes it: the
    // next run cancels the previous controller, but that is 300ms away behind the debounce,
    // which is long enough for the stale response to land and write itself back.
    it('abandons an answer to the previous question when the channel changes', async () => {
      CampaignsAPI.audiencePreview.mockImplementationOnce(
        () => new Promise(() => {})
      );
      const wrapper = mountRecipients({}, { labelIds: [1], inboxId: 7 });
      await vi.advanceTimersByTimeAsync(PREVIEW_DELAY_MS);

      const { signal } = CampaignsAPI.audiencePreview.mock.calls[0][1];
      expect(signal.aborted).toBe(false);

      await wrapper.setProps({ inboxId: 8 });

      expect(signal.aborted).toBe(true);
    });
  });

  it('offers only shared filters, never somebody personal one', () => {
    const wrapper = mountRecipients({
      contactViews: [
        sharedAudience,
        { id: 10, name: 'Mine', shared: false, query: {} },
      ],
    });

    const options = wrapper
      .findComponent('[data-test-id="campaign-recipient-audiences"]')
      .props('options');

    expect(options.map(option => option.value)).toEqual([9]);
  });
});
