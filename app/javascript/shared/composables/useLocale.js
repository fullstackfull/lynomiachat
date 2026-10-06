import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { toIntlLocale } from 'shared/helpers/localeHelper';

/**
 * Composable for locale resolution and validation
 * Provides a normalized, validated locale that works with Intl APIs
 */
export function useLocale() {
  const { locale } = useI18n();

  /**
   * Resolves and validates the current locale for use with Intl APIs
   *
   * Handles multiple fallback scenarios:
   * 1. Normalizes underscore-based tags (pt_BR → pt-BR, zh_CN → zh-CN)
   * 2. Falls back to base language if specific locale unsupported (pt-BR → pt)
   * 3. Falls back to English if base language unsupported, or if the tag is not one Intl will even parse
   *
   * @returns {string} Valid BCP 47 locale tag for Intl APIs
   *
   * @example
   * const { resolvedLocale } = useLocale();
   * new Intl.NumberFormat(resolvedLocale.value).format(1234);
   * new Intl.DateTimeFormat(resolvedLocale.value).format(new Date());
   */
  const resolvedLocale = computed(() => toIntlLocale(locale.value));

  return {
    resolvedLocale,
    // Also expose the raw locale for cases where you need it
    locale,
  };
}
