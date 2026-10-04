// What this phase added to the page: reading the audience the route names, resolving it against the account's own
// shared audiences, and handing it to the campaign dialog. Rendering the dialog from that state is the page's
// existing behaviour and is not re-tested here.
import { ref, computed, nextTick } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import campaign from 'dashboard/i18n/locale/en/campaign.json';
import WhatsAppCampaignsPage from '../WhatsAppCampaignsPage.vue';

const dispatch = vi.fn();
const query = ref({});
const contactViews = ref([]);
const accountLabels = ref([]);

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useStoreGetters: () => ({
    'campaigns/getWhatsAppCampaigns': computed(() => []),
    'customViews/getContactCustomViews': computed(() => contactViews.value),
  }),
  useMapGetter: getter =>
    computed(() =>
      getter === 'labels/getLabels'
        ? accountLabels.value
        : { isFetching: false }
    ),
}));
// One route object whose query reads the current value, as vue-router's own reactive route does: the page captures
// it once in setup and reads `route.query` again on every activation.
const route = {
  name: 'campaigns_whatsapp_index',
  params: {},
  get query() {
    return query.value;
  },
};

vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => route,
  useRouter: () => ({ push: vi.fn() }),
}));

// The page is kept alive in the product (CampaignsPageRouteView), so what matters is activation, not only mount.
const mountPage = async () => {
  const wrapper = mount(
    {
      components: { WhatsAppCampaignsPage },
      template:
        '<keep-alive><WhatsAppCampaignsPage v-if="shown" /></keep-alive>',
      data: () => ({ shown: true }),
    },
    {
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: campaign },
          }),
        ],
        stubs: {
          CampaignLayout: {
            template: '<div><slot name="action" /><slot /></div>',
          },
          CampaignList: true,
          WhatsAppCampaignEmptyState: true,
          WhatsAppCampaignDialog: true,
          ConfirmDeleteCampaignDialog: {
            setup(_, { expose }) {
              expose({ dialogRef: { open: vi.fn() } });
            },
            template: '<div />',
          },
          Spinner: true,
        },
      },
    }
  );
  await flushPromises();
  await nextTick();
  return wrapper;
};

const page = wrapper => wrapper.findComponent(WhatsAppCampaignsPage).vm;

describe('WhatsAppCampaignsPage', () => {
  beforeEach(() => {
    dispatch.mockReset();
    dispatch.mockResolvedValue(undefined);
    query.value = {};
    contactViews.value = [
      { id: 7, name: 'VIP buyers', shared: true },
      { id: 8, name: 'Mine', shared: false },
    ];
    accountLabels.value = [
      { id: 4, title: 'vip' },
      { id: 9, title: 'wholesale' },
    ];
  });

  it('opens nothing, and fetches nothing, when the route names no audience', async () => {
    const wrapper = await mountPage();

    expect(dispatch).not.toHaveBeenCalled();
    expect(page(wrapper).showWhatsAppCampaignDialog).toBeFalsy();
    expect(page(wrapper).initialSharedAudienceIds).toEqual([]);
  });

  it('opens the dialog on the shared audience the route names', async () => {
    query.value = { audience: '7' };
    const wrapper = await mountPage();

    expect(dispatch).toHaveBeenCalledWith('customViews/get', 'contact');
    expect(page(wrapper).showWhatsAppCampaignDialog).toBe(true);
    expect(page(wrapper).initialSharedAudienceIds).toEqual([7]);
  });

  it('prefills nothing for a personal filter, which campaigns may not use', async () => {
    query.value = { audience: '8' };
    const wrapper = await mountPage();

    expect(page(wrapper).initialSharedAudienceIds).toEqual([]);
  });

  it("prefills nothing for an id that is not this account's", async () => {
    query.value = { audience: '999' };
    const wrapper = await mountPage();

    expect(page(wrapper).initialSharedAudienceIds).toEqual([]);
  });

  it('ignores a query value that is not a single positive integer', async () => {
    query.value = { audience: ['7', '8'] };
    const wrapper = await mountPage();

    expect(dispatch).not.toHaveBeenCalled();
    expect(page(wrapper).initialSharedAudienceIds).toEqual([]);
  });

  it('prefills again when the page is re-activated with another audience', async () => {
    query.value = { audience: '7' };
    const wrapper = await mountPage();
    expect(page(wrapper).initialSharedAudienceIds).toEqual([7]);

    // Away and back, as keep-alive does it: deactivated, not unmounted, so onMounted would never run again.
    await wrapper.setData({ shown: false });
    contactViews.value = [
      ...contactViews.value,
      { id: 9, name: 'Recent buyers', shared: true },
    ];
    query.value = { audience: '9' };
    await wrapper.setData({ shown: true });
    await flushPromises();
    await nextTick();

    expect(page(wrapper).initialSharedAudienceIds).toEqual([9]);
  });

  it('opens the dialog on the label the route names', async () => {
    query.value = { label: '9' };
    const wrapper = await mountPage();

    expect(page(wrapper).initialLabelIds).toEqual([9]);
    expect(page(wrapper).initialSharedAudienceIds).toEqual([]);
    // A label is already in the store, so nothing has to be fetched for it.
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("prefills nothing for a label id that is not this account's", async () => {
    query.value = { label: '11' };
    const wrapper = await mountPage();

    expect(page(wrapper).initialLabelIds).toEqual([]);
  });

  it('ignores a label query value that is not a single positive integer', async () => {
    query.value = { label: 'vip' };
    const wrapper = await mountPage();

    expect(page(wrapper).initialLabelIds).toEqual([]);
  });

  it('clears the label prefill when the dialog closes', async () => {
    query.value = { label: '9' };
    const wrapper = await mountPage();
    page(wrapper).closeDialog();

    expect(page(wrapper).initialLabelIds).toEqual([]);
  });
});
