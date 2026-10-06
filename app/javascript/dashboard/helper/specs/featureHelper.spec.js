import { getHelpUrlForFeature } from '../featureHelper';

// docs/global-documentation/12-contextual-help.md: a product "Learn more" resolves to this installation's own
// documentation, and to nothing at all when there is no article for it -- never to a broken or foreign link.
describe('getHelpUrlForFeature', () => {
  const withConfig = config => {
    window.globalConfig = config;
  };

  afterEach(() => {
    window.globalConfig = {};
  });

  it('returns nothing without a feature name', () => {
    expect(getHelpUrlForFeature()).toBeUndefined();
    expect(getHelpUrlForFeature('')).toBeUndefined();
  });

  describe('on a branded installation', () => {
    beforeEach(() =>
      withConfig({
        INSTALLATION_NAME: 'Lynomia Chat',
        DOCUMENTATION_URL: '/docs',
      })
    );

    it('resolves a feature to its own documentation article', () => {
      expect(getHelpUrlForFeature('labels')).toBe('/docs/labels');
      expect(getHelpUrlForFeature('whatsapp_templates')).toBe(
        '/docs/whatsapp-templates'
      );
    });

    it('accepts the hyphenated spelling some call sites use', () => {
      expect(getHelpUrlForFeature('custom-attributes')).toBe(
        '/docs/custom-attributes'
      );
    });

    it('renders no link for a feature with no article yet', () => {
      expect(getHelpUrlForFeature('sla')).toBeUndefined();
      expect(getHelpUrlForFeature('captain')).toBeUndefined();
    });

    it('renders no link when the installation configured no documentation', () => {
      withConfig({ INSTALLATION_NAME: 'Lynomia Chat', DOCUMENTATION_URL: '' });
      expect(getHelpUrlForFeature('labels')).toBeUndefined();
    });

    it('never falls back to someone else’s documentation', () => {
      const urls = [
        'labels',
        'sla',
        'captain',
        'macros',
        'reports',
        'billing',
      ].map(getHelpUrlForFeature);
      expect(urls.filter(Boolean).some(url => url.includes('chatwoot'))).toBe(
        false
      );
    });
  });

  describe('on an unbranded installation', () => {
    beforeEach(() => withConfig({ INSTALLATION_NAME: 'Chatwoot' }));

    it('keeps the upstream destination', () => {
      expect(getHelpUrlForFeature('labels')).toBe('https://chwt.app/hc/labels');
    });
  });
});
