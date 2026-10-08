import { shallowMount } from '@vue/test-utils';
import ChatListHeader from '../ChatListHeader.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref } = await import('vue');
  return {
    useUISettings: () => ({
      uiSettings: ref({}),
      updateUISettings: vi.fn(),
    }),
  };
});

const mountHeader = props =>
  shallowMount(ChatListHeader, {
    props: {
      pageTitle: 'Conversations',
      hasAppliedFilters: false,
      hasActiveFolders: false,
      activeStatus: 'open',
      isOnExpandedLayout: false,
      conversationStats: { allCount: 12 },
      isListLoading: false,
      ...props,
    },
    global: {
      mocks: { $t: key => key },
    },
  });

const contactFilter = { id: 7, name: 'Jane Doe' };

describe('ChatListHeader', () => {
  it('renders the page title and the filter button without filters', () => {
    const wrapper = mountHeader();

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(true);
    expect(wrapper.find('[icon="i-lucide-chevron-left"]').exists()).toBe(false);
  });

  it('keeps the page title and the filter button for non contact filters', () => {
    const wrapper = mountHeader({ hasAppliedFilters: true });

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(true);
    expect(wrapper.find('[icon="i-lucide-chevron-left"]').exists()).toBe(true);
  });

  it('names the contact and hides the filter button when scoped to a contact', () => {
    const wrapper = mountHeader({ hasAppliedFilters: true, contactFilter });

    expect(wrapper.find('h1').text()).toBe('Jane Doe');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(
      false
    );
    expect(wrapper.find('[icon="i-lucide-chevron-left"]').exists()).toBe(true);
  });

  it('falls back to the page title when the scoped contact has no name', () => {
    const wrapper = mountHeader({
      hasAppliedFilters: true,
      contactFilter: { id: 7, name: '' },
    });

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(
      false
    );
  });

  it('keeps the folder controls when a folder is active', () => {
    const wrapper = mountHeader({
      hasAppliedFilters: true,
      hasActiveFolders: true,
      contactFilter,
    });

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('[icon="i-lucide-pen-line"]').exists()).toBe(true);
    expect(wrapper.find('[icon="i-lucide-trash-2"]').exists()).toBe(true);
  });

  // The chip named the active status before this, but as decoration. The only control that could change the
  // status sat behind a button labelled "Sort conversations", so the filter hiding conversations had no
  // visible way out. The chip is now that way out.
  describe('the status chip', () => {
    const findChip = wrapper =>
      wrapper.find('button[aria-label^="CHAT_LIST.STATUS_FILTER.ARIA_LABEL"]');

    it('names the active status and is operable', () => {
      const wrapper = mountHeader({ activeStatus: 'resolved' });
      const chip = findChip(wrapper);

      expect(chip.exists()).toBe(true);
      expect(chip.attributes('type')).toBe('button');
      expect(wrapper.find('woot-label-stub').attributes('label')).toBe(
        'CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.resolved.TEXT'
      );
    });

    it('opens the panel that holds the status filter', async () => {
      const wrapper = mountHeader();
      const openDropdown = vi.fn();
      wrapper.vm.basicFilterRef = { openDropdown };

      await findChip(wrapper).trigger('click');

      expect(openDropdown).toHaveBeenCalled();
    });

    // While an advanced filter or a folder narrows the list, the status filter is not the thing scoping it
    // and the header shows the filter's own name and exit instead.
    it.each([
      ['applied filters', { hasAppliedFilters: true }],
      ['an active folder', { hasActiveFolders: true }],
    ])('is not shown with %s', (_label, props) => {
      expect(findChip(mountHeader(props)).exists()).toBe(false);
    });
  });
});
