import { mount } from '@vue/test-utils';
import DocsLink from '../DocsLink.vue';

let configuredBase;

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    docsLink: key => {
      const slugs = { commerceProviders: 'commerce-provider-support' };
      if (!configuredBase || !slugs[key]) return '';

      return `${configuredBase}/${slugs[key]}`;
    },
  }),
}));

const mountLink = props =>
  mount(DocsLink, {
    props: { articleKey: 'commerceProviders', label: 'Learn more', ...props },
    global: { stubs: { Icon: { template: '<i />' } } },
  });

// The rule this component exists to hold: no article, no link. A dangling "Learn more" is worse than none.
describe('DocsLink', () => {
  beforeEach(() => {
    configuredBase = 'https://docs.example.com';
  });

  it('links to the article for a configured installation', () => {
    const link = mountLink().find('a');

    expect(link.attributes('href')).toBe(
      'https://docs.example.com/commerce-provider-support'
    );
    expect(link.text()).toContain('Learn more');
  });

  it('opens in a new tab without handing the destination a window reference', () => {
    const link = mountLink().find('a');

    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
  });

  it('renders nothing when the installation configured no documentation', () => {
    configuredBase = '';

    expect(mountLink().find('a').exists()).toBe(false);
  });

  it('renders nothing for a key with no article, rather than a link to nowhere', () => {
    expect(
      mountLink({ articleKey: 'notARegistryKey' }).find('a').exists()
    ).toBe(false);
  });
});
