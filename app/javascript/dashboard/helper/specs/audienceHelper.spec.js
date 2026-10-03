import {
  AUDIENCE_QUERY_PARAM,
  audienceConditionFor,
  audienceIdFromQuery,
  findSharedAudience,
  sharedAudiences,
} from '../audienceHelper';

const VIEWS = [
  { id: 3, name: 'VIP buyers', shared: true },
  { id: 4, name: 'My drafts', shared: false },
  { id: 7, name: 'Recent buyers', shared: true },
];

describe('audienceHelper', () => {
  describe('audienceIdFromQuery', () => {
    it('reads a positive integer id', () => {
      expect(audienceIdFromQuery({ [AUDIENCE_QUERY_PARAM]: '7' })).toBe(7);
    });

    it('ignores anything that is not one', () => {
      [
        undefined,
        {},
        { audience: '' },
        { audience: '0' },
        { audience: '-3' },
        { audience: '1.5' },
        { audience: 'all' },
        { audience: ['3'] },
      ].forEach(query => expect(audienceIdFromQuery(query)).toBeNull());
    });
  });

  describe('findSharedAudience', () => {
    it('finds a shared audience of the account', () => {
      expect(findSharedAudience(VIEWS, 7)).toEqual(VIEWS[2]);
    });

    it('does not find a personal filter, an unknown id, or nothing at all', () => {
      expect(findSharedAudience(VIEWS, 4)).toBeUndefined();
      expect(findSharedAudience(VIEWS, 99)).toBeUndefined();
      expect(findSharedAudience(undefined, 7)).toBeUndefined();
    });

    it('keeps only the shared ones', () => {
      expect(sharedAudiences(VIEWS).map(view => view.id)).toEqual([3, 7]);
    });
  });

  describe('audienceConditionFor', () => {
    it('builds an "is in" condition the rule builder can render and save', () => {
      expect(audienceConditionFor(VIEWS[0])).toEqual({
        attribute_key: 'contact_audience',
        filter_operator: 'equal_to',
        values: [{ id: 3, name: 'VIP buyers' }],
        query_operator: 'and',
        custom_attribute_type: '',
      });
    });
  });
});
