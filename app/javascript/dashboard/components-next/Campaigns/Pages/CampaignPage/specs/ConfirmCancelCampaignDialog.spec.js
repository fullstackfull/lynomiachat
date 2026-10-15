import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import campaign from 'dashboard/i18n/locale/en/campaign.json';
import ConfirmCancelCampaignDialog from '../ConfirmCancelCampaignDialog.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// jsdom has no `showModal`, so the real dialog cannot be opened here. The stub keeps what
// this spec is about: the copy in the description slot, and the confirm that cancels.
const DialogStub = {
  props: [
    'title',
    'confirmButtonLabel',
    'isLoading',
    'disableConfirmButton',
    'type',
  ],
  emits: ['confirm', 'close'],
  setup(_props, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template:
    '<div><span>{{ title }}</span><slot name="description" description-id="d" /></div>',
};

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: { ...campaign } },
});

const mountDialog = (cancel = vi.fn(), selectedCampaign = null) =>
  mount(ConfirmCancelCampaignDialog, {
    props: { selectedCampaign },
    global: {
      plugins: [
        i18n,
        createStore({
          getters: { 'campaigns/getUIFlags': () => ({ isUpdating: false }) },
          actions: { 'campaigns/cancel': cancel },
        }),
      ],
      stubs: { Dialog: DialogStub },
    },
  });

const RUNNING = { id: 51, display_id: 4, title: 'Spring sale' };

describe('ConfirmCancelCampaignDialog', () => {
  // STOPPING IS NOT DELETING, and this copy is the only place an operator learns that before
  // committing to it. The two things it has to say are that what already went cannot be
  // recalled, and that the results survive -- which is the whole reason stopping is offered
  // as something other than a delete.
  it('says what stopping does not undo, and what it keeps', () => {
    const text = mountDialog().text();

    expect(text).toContain('cannot be recalled');
    expect(text).toContain('results stay available');
  });

  it('names the campaign being stopped, so it is not the wrong one', () => {
    expect(mountDialog(vi.fn(), RUNNING).text()).toContain('Spring sale');
  });

  // THE NUMBER THE API HANDS OUT, not the primary key. Addressing a campaign by `id` is the
  // defect that made the analytics page show another campaign's results, and the cancel
  // route is addressed the same way.
  it('cancels by the display id the campaigns API addresses', async () => {
    const cancel = vi.fn();
    const wrapper = mountDialog(cancel, RUNNING);

    await wrapper.findComponent(DialogStub).vm.$emit('confirm');

    expect(cancel).toHaveBeenCalledTimes(1);
    expect(cancel.mock.calls[0][1]).toEqual({ id: 4 });
  });

  // A dialog opened with nothing selected must not send a cancel for `undefined`.
  it('asks for nothing when no campaign is selected', async () => {
    const cancel = vi.fn();
    const wrapper = mountDialog(cancel, null);

    await wrapper.findComponent(DialogStub).vm.$emit('confirm');

    expect(cancel).not.toHaveBeenCalled();
  });
});
