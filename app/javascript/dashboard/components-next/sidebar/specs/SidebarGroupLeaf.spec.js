import { mount } from '@vue/test-utils';
import { h } from 'vue';
import SidebarGroupLeaf from '../SidebarGroupLeaf.vue';

vi.mock('../provider', () => ({
  useSidebarContext: () => ({
    resolvePermissions: () => [],
    resolveFeatureFlag: () => '',
  }),
}));

const PolicyStub = {
  props: ['as', 'permissions', 'featureFlag'],
  template: '<li><slot /></li>',
};

const RouterLinkStub = {
  props: ['to'],
  template: '<a><slot /></a>',
};

const mountLeaf = props =>
  mount(SidebarGroupLeaf, {
    props: {
      label: 'Support',
      to: '/support',
      ...props,
    },
    global: {
      stubs: {
        Icon: true,
        Policy: PolicyStub,
        RouterLink: RouterLinkStub,
      },
    },
  });

describe('SidebarGroupLeaf', () => {
  it('renders unread badge when count is present', () => {
    const wrapper = mountLeaf({ badgeCount: 7 });
    const badge = wrapper.find('[data-test-id="sidebar-unread-badge"]');

    expect(badge.exists()).toBe(true);
    expect(badge.text()).toBe('7');
  });

  it('does not render unread badge when count is zero', () => {
    const wrapper = mountLeaf({ badgeCount: 0 });

    expect(wrapper.find('[data-test-id="sidebar-unread-badge"]').exists()).toBe(
      false
    );
  });

  it('caps large unread counts', () => {
    const wrapper = mountLeaf({ badgeCount: 120 });

    expect(wrapper.find('[data-test-id="sidebar-unread-badge"]').text()).toBe(
      '99+'
    );
  });

  it('passes unread count to custom leaf components', () => {
    const wrapper = mountLeaf({
      badgeCount: 4,
      component: leafProps =>
        h(
          'span',
          { 'data-test-id': 'custom-leaf-count' },
          leafProps.badgeCount
        ),
    });

    expect(wrapper.find('[data-test-id="custom-leaf-count"]').text()).toBe('4');
  });

  // Documentation and support live outside the Vue router -- /docs is a server-rendered page, support may be another
  // site entirely -- so a leaf has to be able to render a real anchor, not a router-link.
  describe('an external destination', () => {
    it('renders an anchor that opens in a new tab, safely', () => {
      const wrapper = mountLeaf({ to: null, href: '/docs' });
      const link = wrapper.find('a');

      expect(link.attributes('href')).toBe('/docs');
      expect(link.attributes('target')).toBe('_blank');
      expect(link.attributes('rel')).toBe('noopener noreferrer');
    });

    it('keeps an in-app route a router-link, with no target or rel', () => {
      const wrapper = mountLeaf({ to: '/support' });
      const link = wrapper.find('a');

      expect(link.attributes('href')).toBeUndefined();
      expect(link.attributes('target')).toBeUndefined();
    });

    it('still renders the label', () => {
      expect(
        mountLeaf({ to: null, href: '/docs', label: 'Documentation' }).text()
      ).toContain('Documentation');
    });
  });
});
