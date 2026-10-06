import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import contact from 'dashboard/i18n/locale/en/contact.json';
import ContactsBulkActionBar from '../ContactsBulkActionBar.vue';

const BULK = contact.CONTACTS_BULK_ACTIONS;

// The real bar's parts, reduced to what a test can act on: the select-all checkbox is the model, and each label
// menu is a button that emits the labels it was given.
const BulkSelectBarStub = {
  props: ['modelValue', 'allItems', 'selectAllLabel', 'selectedCountLabel'],
  emits: ['update:modelValue'],
  template: `
    <div>
      <span data-test-id="count">{{ selectedCountLabel }}</span>
      <span data-test-id="select-all-label">{{ selectAllLabel }}</span>
      <button data-test-id="select-all" @click="$emit('update:modelValue', new Set(allItems.map(i => i.id)))" />
      <button data-test-id="select-none" @click="$emit('update:modelValue', new Set())" />
      <slot name="primaryActions" />
      <slot name="actions" />
    </div>
  `,
};

const BulkLabelActionsStub = {
  props: ['type', 'action', 'isLoading', 'disabled'],
  emits: ['assign', 'remove'],
  template: `
    <button
      :data-test-id="action === 'remove' ? 'remove-labels' : 'assign-labels'"
      :disabled="disabled"
      @click="$emit(action === 'remove' ? 'remove' : 'assign', ['vip'])"
    />
  `,
};

const ButtonStub = {
  props: ['label'],
  // Declared, so Vue does not also pass the native click through and emit twice.
  emits: ['click'],
  template: '<button :data-label="label" @click="$emit(\'click\')" />',
};

const mountBar = ({
  visible = [1, 2, 3],
  selected = [],
  policy = true,
  totalCount = 0,
  isWholeViewSelected = false,
  hasMore = false,
} = {}) =>
  mount(ContactsBulkActionBar, {
    props: {
      visibleContactIds: visible,
      selectedContactIds: selected,
      totalCount,
      isWholeViewSelected,
      hasMore,
    },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: contact } }),
      ],
      stubs: {
        BulkSelectBar: BulkSelectBarStub,
        BulkLabelActions: BulkLabelActionsStub,
        Button: ButtonStub,
        // `Policy` renders its slot only for a permitted user; both cases matter here.
        Policy: policy
          ? { props: ['permissions'], template: '<div><slot /></div>' }
          : { props: ['permissions'], template: '<div />' },
      },
      directives: { tooltip: {} },
    },
  });

describe('ContactsBulkActionBar', () => {
  it('says how many are selected, and how many the page can select', () => {
    const wrapper = mountBar({ selected: [1, 2] });

    expect(wrapper.find('[data-test-id="count"]').text()).toBe('2 selected');
    expect(wrapper.find('[data-test-id="select-all-label"]').text()).toBe(
      'Select all (3)'
    );
  });

  it('offers no select-all label when the page holds nothing', () => {
    expect(
      mountBar({ visible: [] }).find('[data-test-id="select-all-label"]').text()
    ).toBe('');
  });

  it('asks for every visible contact when select-all is ticked', async () => {
    const wrapper = mountBar();
    await wrapper.find('[data-test-id="select-all"]').trigger('click');

    expect(wrapper.emitted('toggleAll')).toEqual([[true]]);
  });

  it('asks to deselect when the tick is removed', async () => {
    const wrapper = mountBar({ selected: [1, 2, 3] });
    await wrapper.find('[data-test-id="select-none"]').trigger('click');

    expect(wrapper.emitted('toggleAll')).toEqual([[false]]);
  });

  it('passes the chosen labels up, in both directions', async () => {
    const wrapper = mountBar({ selected: [1] });
    await wrapper.find('[data-test-id="assign-labels"]').trigger('click');
    await wrapper.find('[data-test-id="remove-labels"]').trigger('click');

    expect(wrapper.emitted('assignLabels')).toEqual([[['vip']]]);
    expect(wrapper.emitted('removeLabels')).toEqual([[['vip']]]);
  });

  it('disables both label menus while nothing is selected', () => {
    const wrapper = mountBar({ selected: [] });

    expect(
      wrapper.find('[data-test-id="assign-labels"]').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.find('[data-test-id="remove-labels"]').attributes('disabled')
    ).toBeDefined();
  });

  it('clears the selection on request', async () => {
    const wrapper = mountBar({ selected: [1] });
    const clear = wrapper
      .findAll('button')
      .find(button => button.attributes('data-label') === BULK.CLEAR_SELECTION);
    await clear.trigger('click');

    expect(wrapper.emitted('clearSelection')).toHaveLength(1);
  });

  // D4 (docs/contacts/10-phase-d.md). Only the server can enumerate a view, so the page has to ask for it by
  // name rather than by id.
  describe('acting on a whole view', () => {
    const selectAllMatching = wrapper =>
      wrapper
        .findAll('button')
        .find(button =>
          button.attributes('data-label')?.startsWith('Select all 42')
        );

    it('offers the whole view once the page itself is exhausted', () => {
      const wrapper = mountBar({
        visible: [1, 2, 3],
        selected: [1, 2, 3],
        totalCount: 42,
      });

      expect(selectAllMatching(wrapper).attributes('data-label')).toBe(
        'Select all 42 in this view'
      );
    });

    it('does not offer it while part of the page is still unselected', () => {
      const wrapper = mountBar({
        visible: [1, 2, 3],
        selected: [1],
        totalCount: 42,
      });

      expect(selectAllMatching(wrapper)).toBeUndefined();
    });

    it('does not offer it when the page is the whole view', () => {
      const wrapper = mountBar({
        visible: [1, 2, 3],
        selected: [1, 2, 3],
        totalCount: 3,
      });

      expect(selectAllMatching(wrapper)).toBeUndefined();
    });

    // P0/D6. On a search view the server reports the page size as its count, by design, so gating purely on the
    // total meant this whole feature was silently unreachable there.
    it('is offered on a search view, where the total IS the page size', () => {
      const wrapper = mountBar({
        visible: [1, 2, 3],
        selected: [1, 2, 3],
        totalCount: 3,
        hasMore: true,
      });
      const button = wrapper
        .findAll('button')
        .find(
          b => b.attributes('data-label') === 'Select all results in this view'
        );

      expect(button).toBeDefined();
    });

    it('shows no number when the server did not give a usable one', () => {
      const wrapper = mountBar({
        visible: [1, 2, 3],
        selected: [1, 2, 3],
        totalCount: 3,
        hasMore: true,
      });
      const labels = wrapper
        .findAll('button')
        .map(b => b.attributes('data-label'));

      expect(labels).toContain('Select all results in this view');
      expect(labels.some(l => l?.includes('Select all 3'))).toBe(false);
    });

    it('counts without a number once an uncounted view is selected', () => {
      const wrapper = mountBar({
        visible: [1, 2, 3],
        selected: [1, 2, 3],
        totalCount: 3,
        hasMore: true,
        isWholeViewSelected: true,
      });

      expect(wrapper.find('[data-test-id="count"]').text()).toBe(
        'All results in this view selected'
      );
    });

    it('is still not offered when the page is the whole view and there is no more', () => {
      const wrapper = mountBar({
        visible: [1, 2, 3],
        selected: [1, 2, 3],
        totalCount: 3,
        hasMore: false,
      });
      const labels = wrapper
        .findAll('button')
        .map(b => b.attributes('data-label'));

      expect(labels).not.toContain('Select all results in this view');
      expect(selectAllMatching(wrapper)).toBeUndefined();
    });

    it('asks for the whole view when offered and taken', async () => {
      const wrapper = mountBar({
        visible: [1, 2, 3],
        selected: [1, 2, 3],
        totalCount: 42,
      });
      await selectAllMatching(wrapper).trigger('click');

      expect(wrapper.emitted('selectAllMatching')).toHaveLength(1);
    });

    // The count of ids the browser holds would read as three of forty-two, which is not what is about to happen.
    it('counts the whole view once the whole view is what is selected', () => {
      const wrapper = mountBar({
        visible: [1, 2, 3],
        selected: [1, 2, 3],
        totalCount: 42,
        isWholeViewSelected: true,
      });

      expect(wrapper.find('[data-test-id="count"]').text()).toBe(
        'All 42 selected'
      );
      expect(selectAllMatching(wrapper)).toBeUndefined();
    });
  });

  it('offers delete only to a user the policy admits', () => {
    const allowed = mountBar({ selected: [1], policy: true });
    const refused = mountBar({ selected: [1], policy: false });
    const deleteButton = wrapper =>
      wrapper
        .findAll('button')
        .find(
          button => button.attributes('data-label') === BULK.DELETE_CONTACTS
        );

    expect(deleteButton(allowed)).toBeDefined();
    expect(deleteButton(refused)).toBeUndefined();
  });
});
