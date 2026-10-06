import { mount } from '@vue/test-utils';
import ConversationBasicFilter from '../ConversationBasicFilter.vue';

const getters = {
  getChatStatusFilter: 'open',
  getChatSortFilter: 'last_activity_at_desc',
};

vi.mock('dashboard/composables/store.js', async () => {
  const { computed } = await import('vue');
  return {
    useMapGetter: key => computed(() => getters[key]),
  };
});

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const mountFilter = props =>
  mount(ConversationBasicFilter, {
    props: { isOnExpandedLayout: false, ...props },
    global: {
      stubs: {
        NextButton: { template: '<button />', inheritAttrs: false },
        SelectMenu: { template: '<div />' },
      },
    },
  });

describe('ConversationBasicFilter', () => {
  // The panel holds the status filter as well as the sort order. Labelling its trigger "Sort conversations"
  // is what made the status filter undiscoverable, so the label has to follow what is actually inside.
  it('names filtering and sorting on the trigger while the status filter is in the panel', () => {
    const wrapper = mountFilter();

    expect(wrapper.vm.triggerLabel).toBe(
      'CHAT_LIST.FILTER_AND_SORT_TOOLTIP_LABEL'
    );
  });

  it('names sorting alone when the status filter is not in the panel', () => {
    const wrapper = mountFilter({ showStatusFilter: false });

    expect(wrapper.vm.triggerLabel).toBe('CHAT_LIST.SORT_TOOLTIP_LABEL');
  });

  it('opens the panel when the header asks it to', async () => {
    const wrapper = mountFilter();
    expect(wrapper.vm.showActionsDropdown).toBe(false);

    wrapper.vm.openDropdown();
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.showActionsDropdown).toBe(true);
  });

  // Applying the choice, mirroring it into the store and persisting it all belong to ChatList, which owns
  // both halves of the saved status/order pair. This component only reports what was picked.
  it('reports the choice and applies nothing itself', () => {
    const wrapper = mountFilter();

    wrapper.vm.changeFilter('resolved', 'status');
    wrapper.vm.changeFilter('created_at_asc', 'sort');

    expect(wrapper.emitted('changeFilter')).toEqual([
      ['resolved', 'status'],
      ['created_at_asc', 'sort'],
    ]);
  });
});
