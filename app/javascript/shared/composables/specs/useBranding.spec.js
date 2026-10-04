import { useBranding } from '../useBranding';
import { useMapGetter } from 'dashboard/composables/store.js';

// Mock the store composable
vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: vi.fn(),
}));

describe('useBranding', () => {
  let mockGlobalConfig;
  let mockIsACustomBrandedInstance;

  const wireGetters = () => {
    useMapGetter.mockImplementation(getter =>
      getter === 'globalConfig/isACustomBrandedInstance'
        ? mockIsACustomBrandedInstance
        : mockGlobalConfig
    );
  };

  beforeEach(() => {
    mockGlobalConfig = {
      value: {
        installationName: 'MyCompany',
      },
    };
    mockIsACustomBrandedInstance = { value: true };

    wireGetters();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('installationName', () => {
    it('should expose the installation name for use as an i18n parameter', () => {
      const { installationName } = useBranding();

      expect(installationName.value).toBe('MyCompany');
    });

    it('should be undefined when globalConfig is not available', () => {
      mockGlobalConfig.value = undefined;

      const { installationName } = useBranding();

      expect(installationName.value).toBeUndefined();
    });
  });

  describe('replaceInstallationName', () => {
    it('should replace "Chatwoot" with installation name when both text and installation name are provided', () => {
      const { replaceInstallationName } = useBranding();
      const result = replaceInstallationName('Welcome to Chatwoot');

      expect(result).toBe('Welcome to MyCompany');
    });

    it('should replace multiple occurrences of "Chatwoot"', () => {
      const { replaceInstallationName } = useBranding();
      const result = replaceInstallationName(
        'Chatwoot is great! Use Chatwoot today.'
      );

      expect(result).toBe('MyCompany is great! Use MyCompany today.');
    });

    it('should return original text when installation name is not provided', () => {
      mockGlobalConfig.value = {};

      const { replaceInstallationName } = useBranding();
      const result = replaceInstallationName('Welcome to Chatwoot');

      expect(result).toBe('Welcome to Chatwoot');
    });

    it('should return original text when globalConfig is not available', () => {
      mockGlobalConfig.value = undefined;

      const { replaceInstallationName } = useBranding();
      const result = replaceInstallationName('Welcome to Chatwoot');

      expect(result).toBe('Welcome to Chatwoot');
    });

    it('should return original text when text is empty or null', () => {
      const { replaceInstallationName } = useBranding();

      expect(replaceInstallationName('')).toBe('');
      expect(replaceInstallationName(null)).toBe(null);
      expect(replaceInstallationName(undefined)).toBe(undefined);
    });

    it('should handle text without "Chatwoot" gracefully', () => {
      const { replaceInstallationName } = useBranding();
      const result = replaceInstallationName('Welcome to our platform');

      expect(result).toBe('Welcome to our platform');
    });

    it('should replace "Chatwoot" regardless of casing', () => {
      const { replaceInstallationName } = useBranding();
      const result = replaceInstallationName(
        'Welcome to chatwoot, Chatwoot and CHATWOOT'
      );

      expect(result).toBe('Welcome to MyCompany, MyCompany and MyCompany');
    });

    it('should handle special characters in installation name', () => {
      mockGlobalConfig.value = {
        installationName: 'My-Company & Co.',
      };

      const { replaceInstallationName } = useBranding();
      const result = replaceInstallationName('Welcome to Chatwoot');

      expect(result).toBe('Welcome to My-Company & Co.');
    });
  });

  describe('brandLink', () => {
    it('keeps the upstream link on an installation that has not been rebranded', () => {
      mockIsACustomBrandedInstance = { value: false };
      mockGlobalConfig.value = {
        installationName: 'Chatwoot',
        documentationURL: '',
      };
      wireGetters();

      const { brandLink } = useBranding();

      expect(brandLink('documentation', 'https://upstream.example/docs')).toBe(
        'https://upstream.example/docs'
      );
    });

    it('returns the configured link instead of the upstream one on a branded installation', () => {
      mockGlobalConfig.value = {
        installationName: 'MyCompany',
        documentationURL: 'https://docs.mycompany.example',
        supportURL: 'https://help.mycompany.example',
        changelogURL: 'https://mycompany.example/changelog',
      };
      wireGetters();

      const { brandLink } = useBranding();

      expect(brandLink('documentation', 'https://upstream.example/docs')).toBe(
        'https://docs.mycompany.example'
      );
      expect(brandLink('support', 'https://upstream.example/status')).toBe(
        'https://help.mycompany.example'
      );
      expect(brandLink('changelog', 'https://upstream.example/changelog')).toBe(
        'https://mycompany.example/changelog'
      );
    });

    it('returns an empty string on a branded installation with nothing configured, so callers render no link', () => {
      const { brandLink } = useBranding();

      expect(brandLink('documentation', 'https://upstream.example/docs')).toBe(
        ''
      );
      expect(brandLink('support', 'https://upstream.example/status')).toBe('');
      expect(brandLink('changelog', 'https://upstream.example/changelog')).toBe(
        ''
      );
    });

    it('never leaks the upstream link when globalConfig is unavailable on a branded installation', () => {
      mockGlobalConfig.value = undefined;
      wireGetters();

      const { brandLink } = useBranding();

      expect(brandLink('documentation', 'https://upstream.example/docs')).toBe(
        ''
      );
    });
  });
});
