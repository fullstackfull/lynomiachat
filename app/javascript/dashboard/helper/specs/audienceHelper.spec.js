import {
  AUDIENCE_QUERY_PARAM,
  LABEL_QUERY_PARAM,
  audienceConditionFor,
  audienceIdFromQuery,
  findAccountLabel,
  findSharedAudience,
  labelIdFromQuery,
  sharedAudiences,
  audienceReturnRoute,
  returnRouteFromQuery,
  RETURN_TO_QUERY_PARAM,
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

  describe('labelIdFromQuery', () => {
    it('reads a label id the query names', () => {
      expect(labelIdFromQuery({ [LABEL_QUERY_PARAM]: '4' })).toBe(4);
    });

    it('is null when the query names none', () => {
      expect(labelIdFromQuery({})).toBeNull();
      expect(labelIdFromQuery(undefined)).toBeNull();
    });

    it('refuses anything that is not a single positive integer', () => {
      expect(labelIdFromQuery({ [LABEL_QUERY_PARAM]: ['4'] })).toBeNull();
      expect(labelIdFromQuery({ [LABEL_QUERY_PARAM]: '0' })).toBeNull();
      expect(labelIdFromQuery({ [LABEL_QUERY_PARAM]: '-4' })).toBeNull();
      expect(labelIdFromQuery({ [LABEL_QUERY_PARAM]: 'vip' })).toBeNull();
    });

    it('does not read the audience parameter, and vice versa', () => {
      expect(labelIdFromQuery({ [AUDIENCE_QUERY_PARAM]: '4' })).toBeNull();
      expect(audienceIdFromQuery({ [LABEL_QUERY_PARAM]: '4' })).toBeNull();
    });
  });

  describe('findAccountLabel', () => {
    const LABELS = [
      { id: 4, title: 'vip' },
      { id: 9, title: 'wholesale' },
    ];

    it("finds one of the account's labels by id", () => {
      expect(findAccountLabel(LABELS, 9)).toEqual({
        id: 9,
        title: 'wholesale',
      });
    });

    it('finds nothing for an id the account does not have', () => {
      expect(findAccountLabel(LABELS, 11)).toBeUndefined();
      expect(findAccountLabel(undefined, 4)).toBeUndefined();
    });
  });
});

describe('audienceReturnRoute', () => {
  it('sends the user to Contacts and remembers where to come back to', () => {
    expect(audienceReturnRoute('campaigns_whatsapp_index')).toEqual({
      name: 'contacts_dashboard_index',
      query: { [RETURN_TO_QUERY_PARAM]: 'campaigns_whatsapp_index' },
    });
  });
});

describe('returnRouteFromQuery', () => {
  it('reads back a route it knows', () => {
    expect(returnRouteFromQuery({ returnTo: 'campaigns_whatsapp_index' })).toBe(
      'campaigns_whatsapp_index'
    );
    expect(returnRouteFromQuery({ returnTo: 'campaigns_sms_index' })).toBe(
      'campaigns_sms_index'
    );
  });

  it('ignores a destination it does not know, so the parameter cannot aim someone elsewhere', () => {
    expect(returnRouteFromQuery({ returnTo: 'super_admin' })).toBeNull();
    expect(
      returnRouteFromQuery({ returnTo: 'https://example.com' })
    ).toBeNull();
    expect(
      returnRouteFromQuery({ returnTo: '/app/accounts/1/settings' })
    ).toBeNull();
  });

  it('has no opinion when the query says nothing', () => {
    expect(returnRouteFromQuery({})).toBeNull();
    expect(returnRouteFromQuery(undefined)).toBeNull();
  });
});
