import {
  hasUnresolvedTrunkPrefix,
  stripPhoneFormatting,
  toE164,
} from '../phoneNumber';

describe('phoneNumber', () => {
  describe('stripPhoneFormatting', () => {
    it('removes the punctuation people type', () => {
      expect(stripPhoneFormatting('(055) 512-3456')).toBe('0555123456');
      expect(stripPhoneFormatting('+965 2220 1234')).toBe('+96522201234');
      expect(stripPhoneFormatting('0551.112.233')).toBe('0551112233');
      expect(stripPhoneFormatting('+44 20/7123 4567')).toBe('+442071234567');
    });

    it('removes the bidirectional marks an Arabic page copy carries', () => {
      expect(stripPhoneFormatting('‎+965 22201234‏')).toBe('+96522201234');
    });

    it('turns an international 00 prefix into +', () => {
      expect(stripPhoneFormatting('0096522201234')).toBe('+96522201234');
      expect(stripPhoneFormatting('00 965 2220 1234')).toBe('+96522201234');
    });

    it('leaves a single leading zero alone', () => {
      expect(stripPhoneFormatting('0551112233')).toBe('0551112233');
    });

    it('is safe on empty and nullish input', () => {
      expect(stripPhoneFormatting('')).toBe('');
      expect(stripPhoneFormatting(null)).toBe('');
      expect(stripPhoneFormatting(undefined)).toBe('');
    });
  });

  describe('toE164', () => {
    it('normalizes an international number without needing a region', () => {
      expect(toE164('+965 2220 1234')).toBe('+96522201234');
      expect(toE164('00 965 2220 1234')).toBe('+96522201234');
    });

    it('strips the trunk prefix when the region is explicit', () => {
      expect(toE164('0551112233', 'SA')).toBe('+966551112233');
      expect(toE164('(055) 111-2233', 'SA')).toBe('+966551112233');
      expect(toE164('07911 123456', 'GB')).toBe('+447911123456');
    });

    it('normalizes a national number that carries no trunk prefix', () => {
      expect(toE164('551112233', 'SA')).toBe('+966551112233');
      expect(toE164('22201234', 'KW')).toBe('+96522201234');
    });

    // The rule this whole helper exists for.
    it('refuses to guess a local number when no region is explicit', () => {
      expect(toE164('0551112233')).toBeNull();
      expect(toE164('0551112233', null)).toBeNull();
      expect(toE164('551112233')).toBeNull();
    });

    it('returns null for a number the library rejects', () => {
      expect(toE164('+9650551112233')).toBeNull();
      expect(toE164('12', 'SA')).toBeNull();
      expect(toE164('+1')).toBeNull();
    });

    it('is safe on empty and nullish input', () => {
      expect(toE164('')).toBeNull();
      expect(toE164(null, 'SA')).toBeNull();
      expect(toE164(undefined)).toBeNull();
    });

    it('is idempotent, so re-normalizing an emitted value is stable', () => {
      const once = toE164('0551112233', 'SA');
      expect(toE164(once, 'SA')).toBe(once);
      expect(toE164(once)).toBe(once);
    });

    it('prefers the number’s own country over the given region', () => {
      // A Kuwaiti number pasted while the form says Saudi Arabia stays Kuwaiti.
      expect(toE164('+96522201234', 'SA')).toBe('+96522201234');
    });
  });

  describe('hasUnresolvedTrunkPrefix', () => {
    it('flags a trunk-prefixed number with no explicit region', () => {
      expect(hasUnresolvedTrunkPrefix('0551112233')).toBe(true);
      expect(hasUnresolvedTrunkPrefix('(055) 111-2233', null)).toBe(true);
    });

    it('does not flag it once a region is explicit', () => {
      expect(hasUnresolvedTrunkPrefix('0551112233', 'SA')).toBe(false);
    });

    it('does not flag an international number', () => {
      expect(hasUnresolvedTrunkPrefix('+96522201234')).toBe(false);
      expect(hasUnresolvedTrunkPrefix('0096522201234')).toBe(false);
    });

    it('does not flag a number without a trunk prefix', () => {
      expect(hasUnresolvedTrunkPrefix('551112233')).toBe(false);
      expect(hasUnresolvedTrunkPrefix('')).toBe(false);
    });
  });
});
