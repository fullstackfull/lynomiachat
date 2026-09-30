import {
  formatAmount,
  hasTracking,
  relativeTime,
  safeAdminUrl,
  safeHttpsUrl,
  trackingMessage,
} from '../commerceHelper';

describe('commerceHelper', () => {
  describe('safeHttpsUrl', () => {
    it('keeps absolute https links', () => {
      expect(safeHttpsUrl('https://track.example.com/a?b=1')).toBe(
        'https://track.example.com/a?b=1'
      );
    });

    it.each([
      'http://track.example.com',
      // eslint-disable-next-line no-script-url -- a script URL is the input under test
      'javascript:alert(1)',
      'https://user:pass@track.example.com',
      '/relative',
      '',
      null,
    ])('rejects %s', url => {
      expect(safeHttpsUrl(url)).toBeNull();
    });
  });

  it('allows http admin links for trusted development stores but never scripts', () => {
    expect(safeAdminUrl('http://localhost:8081/wp-admin/admin.php?id=1')).toBe(
      'http://localhost:8081/wp-admin/admin.php?id=1'
    );
    // eslint-disable-next-line no-script-url -- a script URL is the input under test
    expect(safeAdminUrl('javascript:alert(1)')).toBeNull();
  });

  it('formats amounts in the order currency', () => {
    expect(formatAmount('284.75', 'SAR', 'en')).toContain('284.75');
    expect(formatAmount('284.75', 'SAR', 'en')).toContain('SAR');
    expect(formatAmount('abc', 'SAR', 'en')).toBe('abc SAR');
  });

  it('formats the age of stale data in the agent language', () => {
    const now = Date.parse('2026-09-30T12:18:00Z');
    expect(relativeTime('2026-09-30T12:00:00Z', 'en', now)).toBe(
      '18 minutes ago'
    );
    expect(relativeTime('2026-09-30T12:00:00Z', 'ar', now)).toMatch(/دقيقة/);
    expect(relativeTime('2026-09-30T09:00:00Z', 'en', now)).toBe('3 hours ago');
  });

  describe('tracking', () => {
    const t = (key, params) => `${key} ${JSON.stringify(params)}`;

    it('has no tracking when the provider has none', () => {
      expect(hasTracking({ tracking: null })).toBe(false);
      expect(hasTracking({ tracking: { number: null, url: 'http://x' } })).toBe(
        false
      );
    });

    it('builds the message from the number and a safe URL only', () => {
      const order = {
        order_number: '22',
        tracking: { number: 'ARX1', url: 'https://t.example.com/ARX1' },
      };
      expect(trackingMessage(order, t)).toBe(
        'COMMERCE.PANEL.TRACKING_MESSAGE.FULL {"orderNumber":"22","number":"ARX1","url":"https://t.example.com/ARX1"}'
      );
      expect(
        trackingMessage(
          { order_number: '22', tracking: { number: 'ARX1', url: 'http://x' } },
          t
        )
      ).toBe(
        'COMMERCE.PANEL.TRACKING_MESSAGE.NUMBER {"orderNumber":"22","number":"ARX1"}'
      );
    });
  });
});
