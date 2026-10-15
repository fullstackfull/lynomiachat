// The three scroll modes of the shared Dialog.
//
// WHY THIS EXISTS. `scrollBody` was briefly folded into `overflowYAuto`, which silently changed the
// layout of eight dialogs that had never asked for it. A scrolling body is a SECOND, closer clipping
// box, and this product's ComboBox renders its dropdown as an in-flow `absolute` child with no teleport
// (ComboBoxDropdown.vue:69) -- so every dialog with a combobox in it lost the room that dropdown used
// to have. Fifty-three components mount this one; nothing pinned which mode each got.
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Dialog from '../Dialog.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: { DIALOG: { BUTTONS: { CANCEL: 'Cancel', CONFIRM: 'Confirm' } } },
  },
});

// jsdom implements neither method, and Dialog calls them on open and close.
beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
});

const open = async props => {
  const wrapper = mount(Dialog, {
    props: { title: 'A dialog', ...props },
    slots: { default: '<p class="body-content">content</p>' },
    global: {
      plugins: [i18n],
      stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
    },
  });
  wrapper.vm.open();
  await wrapper.vm.$nextTick();
  return wrapper;
};

/// The wrapper only exists in `scrollBody` mode; otherwise the slot's children stay direct flex items
/// of the form, which is what `display: contents` buys.
const bodyScroller = wrapper =>
  wrapper
    .findAll('form > div')
    .find(d => d.classes().includes('overflow-y-auto'));

describe('Dialog scroll modes', () => {
  it('scrolls nothing by default, and lets content overflow the box', async () => {
    const wrapper = await open();

    expect(wrapper.find('dialog').classes()).toContain('overflow-visible');
    expect(bodyScroller(wrapper)).toBeUndefined();
    expect(wrapper.find('form').classes().join(' ')).not.toContain('max-h-');
    wrapper.unmount();
  });

  // The original meaning, which eight dialogs still rely on: the WHOLE dialog scrolls, so the only
  // clipping edge is the form's own border box.
  it('overflowYAuto scrolls the whole dialog and adds no inner scroller', async () => {
    const wrapper = await open({ overflowYAuto: true });

    expect(wrapper.find('dialog').classes()).toContain('overflow-y-auto');
    expect(wrapper.find('dialog').classes()).not.toContain('overflow-hidden');
    expect(bodyScroller(wrapper)).toBeUndefined();
    wrapper.unmount();
  });

  // The campaign create flows: the body scrolls so the title and footer stay put.
  it('scrollBody caps the form and scrolls only the body', async () => {
    const wrapper = await open({ scrollBody: true });

    expect(wrapper.find('dialog').classes()).toContain('overflow-hidden');
    expect(wrapper.find('form').classes().join(' ')).toContain('max-h-');

    const scroller = bodyScroller(wrapper);
    expect(scroller).toBeDefined();
    expect(scroller.find('.body-content').exists()).toBe(true);
    // The footer is outside it, which is the entire point.
    expect(scroller.find('button').exists()).toBe(false);
    wrapper.unmount();
  });

  it.each([
    ['default', {}],
    ['overflowYAuto', { overflowYAuto: true }],
    ['scrollBody', { scrollBody: true }],
  ])('keeps the body content in the tree: %s', async (_name, props) => {
    const wrapper = await open(props);

    expect(wrapper.find('.body-content').exists()).toBe(true);
    wrapper.unmount();
  });
});
