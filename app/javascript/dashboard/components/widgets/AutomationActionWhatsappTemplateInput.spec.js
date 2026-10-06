import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { useMapGetter } from 'dashboard/composables/store';
import AutomationActionWhatsappTemplateInput from './AutomationActionWhatsappTemplateInput.vue';

vi.mock('dashboard/composables/store', () => ({ useMapGetter: vi.fn() }));

const SingleSelectStub = {
  name: 'SingleSelect',
  props: ['modelValue', 'options', 'dropdownMaxHeight', 'placeholder'],
  emits: ['update:modelValue'],
  template: '<div class="single-select" />',
};
const InputStub = {
  name: 'NextInput',
  props: ['modelValue', 'size', 'label'],
  emits: ['update:modelValue'],
  template: '<input :value="modelValue" />',
};

// Only this inbox's own synced snapshot, which is what the real send gate searches.
const APPROVED = {
  name: 'cart_reminder',
  language: 'en',
  status: 'approved',
  category: 'MARKETING',
  components: [{ type: 'BODY', text: 'Hi {{1}}, your cart is waiting: {{2}}' }],
};
const OTHER_INBOX_TEMPLATE = {
  name: 'other_waba_only',
  language: 'en',
  status: 'approved',
  category: 'UTILITY',
  components: [{ type: 'BODY', text: 'hi' }],
};

const inboxes = ref([
  { id: 7, name: 'KW Pharmacy' },
  { id: 9, name: 'Other WABA' },
]);
const templatesByInbox = { 7: [APPROVED], 9: [OTHER_INBOX_TEMPLATE] };

const build = (modelValue = {}) =>
  mount(AutomationActionWhatsappTemplateInput, {
    props: { modelValue },
    global: {
      stubs: { SingleSelect: SingleSelectStub, NextInput: InputStub },
      mocks: { $t: key => key },
    },
  });

const selects = wrapper => wrapper.findAllComponents(SingleSelectStub);

describe('AutomationActionWhatsappTemplateInput', () => {
  beforeEach(() => {
    useMapGetter.mockImplementation(name =>
      name === 'inboxes/getWhatsAppInboxes'
        ? inboxes
        : ref(inboxId => templatesByInbox[inboxId] || [])
    );
  });

  it('offers only the WhatsApp inboxes of this account', () => {
    const wrapper = build();

    expect(selects(wrapper)[0].props('options')).toEqual([
      { id: 7, name: 'KW Pharmacy' },
      { id: 9, name: 'Other WABA' },
    ]);
  });

  it('offers no template until an inbox is chosen', () => {
    expect(selects(build())).toHaveLength(1);
  });

  it('offers the chosen inbox templates, named with their language', async () => {
    const wrapper = build();
    await selects(wrapper)[0].vm.$emit('update:modelValue', { id: 7 });

    expect(selects(wrapper)[1].props('options')).toEqual([
      { id: 'cart_reminder::en', name: 'cart_reminder (en)' },
    ]);
  });

  // Another inbox's template is not merely discouraged here, it is absent: the list is that inbox's own snapshot.
  it('never offers another inbox or WABA template', async () => {
    const wrapper = build();
    await selects(wrapper)[0].vm.$emit('update:modelValue', { id: 7 });

    const names = selects(wrapper)[1]
      .props('options')
      .map(option => option.id);
    expect(names).not.toContain('other_waba_only::en');
  });

  it('emits the inbox, template name and language the backend action reads', async () => {
    const wrapper = build();
    await selects(wrapper)[0].vm.$emit('update:modelValue', { id: 7 });
    await selects(wrapper)[1].vm.$emit('update:modelValue', {
      id: 'cart_reminder::en',
    });

    const emitted = wrapper.emitted('update:modelValue').at(-1)[0];
    expect(emitted).toMatchObject({
      inbox_id: 7,
      name: 'cart_reminder',
      language: 'en',
    });
    expect(emitted.params).toHaveProperty('body');
  });

  it('renders one input per variable the template actually needs', async () => {
    const wrapper = build();
    await selects(wrapper)[0].vm.$emit('update:modelValue', { id: 7 });
    await selects(wrapper)[1].vm.$emit('update:modelValue', {
      id: 'cart_reminder::en',
    });

    expect(wrapper.findAllComponents(InputStub)).toHaveLength(2);
  });

  // A mapping left over from a previous template would otherwise be submitted against the new one.
  it('clears the template and its variables when the inbox changes', async () => {
    const wrapper = build();
    await selects(wrapper)[0].vm.$emit('update:modelValue', { id: 7 });
    await selects(wrapper)[1].vm.$emit('update:modelValue', {
      id: 'cart_reminder::en',
    });
    await selects(wrapper)[0].vm.$emit('update:modelValue', { id: 9 });

    const emitted = wrapper.emitted('update:modelValue').at(-1)[0];
    expect(emitted).toMatchObject({ inbox_id: 9, name: null, language: null });
    expect(emitted.params).toEqual({});
  });

  it('says so when the chosen inbox has no approved template', async () => {
    const wrapper = build();
    useMapGetter.mockImplementation(name =>
      name === 'inboxes/getWhatsAppInboxes' ? inboxes : ref(() => [])
    );
    const empty = build();
    await selects(empty)[0].vm.$emit('update:modelValue', { id: 7 });

    expect(empty.text()).toContain('NONE_APPROVED');
    expect(wrapper.exists()).toBe(true);
  });
});
