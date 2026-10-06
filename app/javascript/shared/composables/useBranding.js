/**
 * Composable for branding-related utilities
 * Provides methods to customize text with installation-specific branding
 */
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store.js';
import { documentationArticleUrl } from 'dashboard/helper/documentationLinks';

// The InstallationConfig key behind each kind of product link, as globalConfig exposes it.
const BRAND_LINK_CONFIG_KEYS = {
  documentation: 'documentationURL',
  support: 'supportURL',
  changelog: 'changelogURL',
};

export function useBranding() {
  const globalConfig = useMapGetter('globalConfig/get');
  const isACustomBrandedInstance = useMapGetter(
    'globalConfig/isACustomBrandedInstance'
  );

  /**
   * The installation's own name, for strings that carry an `{installationName}` placeholder.
   * vue-i18n drops a named placeholder nobody supplies, so a branded string must be translated as
   * `t(key, { installationName })` -- the plain `t(key)` renders a gap where the product name belongs.
   */
  const installationName = computed(() => globalConfig.value?.installationName);
  /**
   * Replaces "Chatwoot" (any casing) in text with the installation name from
   * global config
   * @param {string} text - The text to process
   * @returns {string} - Text with "Chatwoot" replaced by installation name
   */
  const replaceInstallationName = text => {
    if (!text) return text;
    if (!installationName.value) return text;

    return text.replace(/chatwoot/gi, installationName.value);
  };

  /**
   * Resolves an external product link. An upstream deep link is only the right destination on an upstream
   * installation; a branded one gets whatever it configured for that kind of link, and no link at all when it
   * configured none -- which is already how every help link behind CustomBrandPolicyWrapper behaves. Callers
   * must therefore treat an empty result as "render no link".
   * @param {'documentation'|'support'|'changelog'} kind - which configured link to use
   * @param {string} upstreamUrl - the destination to keep on an unbranded installation
   * @returns {string} - the URL to link to, or '' for no link
   */
  const brandLink = (kind, upstreamUrl = '') => {
    if (!isACustomBrandedInstance.value) return upstreamUrl;

    return globalConfig.value?.[BRAND_LINK_CONFIG_KEYS[kind]] || '';
  };

  /**
   * Resolves one documentation article from the registry against this installation's documentation URL.
   * Keyed on the article's stable slug rather than on a database id, so a link survives the content being reseeded
   * (dashboard/helper/documentationLinks.js). Returns '' when the installation has no documentation configured, and
   * callers render no link in that case.
   * @param {string} key - a key of DOC_ARTICLES
   * @returns {string} - the article URL, or '' for no link
   */
  const docsLink = key =>
    documentationArticleUrl(brandLink('documentation'), key);

  return {
    installationName,
    replaceInstallationName,
    brandLink,
    docsLink,
  };
}
