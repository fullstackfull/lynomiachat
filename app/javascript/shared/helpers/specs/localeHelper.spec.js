import { toIntlLocale } from '../localeHelper';

describe('toIntlLocale', () => {
  it('passes a tag Intl already accepts straight through', () => {
    expect(toIntlLocale('en')).toBe('en');
    expect(toIntlLocale('ar')).toBe('ar');
    expect(toIntlLocale('pt-BR')).toBe('pt-BR');
  });

  it('turns a Rails-shaped tag into the hyphenated form Intl wants', () => {
    expect(toIntlLocale('pt_BR')).toBe('pt-BR');
    expect(toIntlLocale('zh_CN')).toBe('zh-CN');
  });

  // The case this helper exists for: Chromium derives navigator.language from the host, and on a POSIX host it
  // reports a tag Intl refuses to parse at all. Before this, that threw a RangeError out of whichever component
  // was formatting a date or a number.
  it('recovers the base language from a tag Intl will not parse', () => {
    expect(toIntlLocale('en-US@posix')).toBe('en');
    expect(toIntlLocale('pt_BR.UTF-8')).toBe('pt');
  });

  it('falls back to English when nothing in the tag is usable', () => {
    expect(toIntlLocale('@@@')).toBe('en');
    expect(toIntlLocale('')).toBe('en');
    expect(toIntlLocale(null)).toBe('en');
    expect(toIntlLocale(undefined)).toBe('en');
  });

  it('honours a caller that wants a different fallback', () => {
    expect(toIntlLocale('@@@', 'ar')).toBe('ar');
  });

  it('never throws, whatever it is handed', () => {
    expect(() => toIntlLocale({})).not.toThrow();
    expect(() => toIntlLocale(42)).not.toThrow();
  });
});
