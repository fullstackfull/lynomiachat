import {
  conditionsOf,
  conditionCount,
  summariseCondition,
  summariseAudience,
} from '../audienceSummary';

// The builder's vocabulary, in the shape `useContactFilterContext` produces.
const filterTypes = [
  {
    attributeKey: 'country_code',
    attributeName: 'Country',
    filterOperators: [
      { value: 'equal_to', label: 'is' },
      { value: 'not_equal_to', label: 'is not' },
    ],
    options: [
      { id: 'KW', name: 'Kuwait' },
      { id: 'SA', name: 'Saudi Arabia' },
    ],
  },
  {
    attributeKey: 'commerce_orders_count',
    attributeName: 'Orders',
    filterOperators: [{ value: 'is_greater_than', label: 'is greater than' }],
  },
  {
    attributeKey: 'labels',
    attributeName: 'Labels',
    filterOperators: [{ value: 'equal_to', label: 'is' }],
    options: [
      { id: 1, name: 'vip' },
      { id: 2, name: 'gold' },
      { id: 3, name: 'silver' },
      { id: 4, name: 'bronze' },
    ],
  },
];

describe('conditionsOf', () => {
  it('reads the payload a saved filter stores', () => {
    expect(conditionsOf({ payload: [{ attribute_key: 'name' }] })).toEqual([
      { attribute_key: 'name' },
    ]);
  });

  it('accepts a bare array, which a record not saved through the builder can carry', () => {
    expect(conditionsOf([{ attribute_key: 'name' }])).toEqual([
      { attribute_key: 'name' },
    ]);
  });

  it('is empty for a query that has none, rather than throwing', () => {
    expect(conditionsOf(undefined)).toEqual([]);
    expect(conditionsOf(null)).toEqual([]);
    expect(conditionsOf({})).toEqual([]);
    expect(conditionsOf({ payload: null })).toEqual([]);
  });
});

describe('conditionCount', () => {
  it('counts the conditions, which is the only measure available without evaluating the filter', () => {
    expect(conditionCount({ payload: [{}, {}, {}] })).toBe(3);
    expect(conditionCount({})).toBe(0);
  });
});

describe('summariseCondition', () => {
  it('names the attribute, the operator and the value the way the builder does', () => {
    const summary = summariseCondition(
      {
        attribute_key: 'country_code',
        filter_operator: 'equal_to',
        values: ['KW'],
      },
      filterTypes
    );

    expect(summary).toBe('Country is Kuwait');
  });

  it('resolves a value stored as an id-and-name object', () => {
    const summary = summariseCondition(
      {
        attribute_key: 'labels',
        filter_operator: 'equal_to',
        values: [{ id: 1, name: 'vip' }],
      },
      filterTypes
    );

    expect(summary).toBe('Labels is vip');
  });

  it('lists the first few values and counts the rest, so a long condition stays one line', () => {
    const summary = summariseCondition(
      {
        attribute_key: 'labels',
        filter_operator: 'equal_to',
        values: [1, 2, 3, 4],
      },
      filterTypes
    );

    expect(summary).toBe('Labels is vip, gold, silver +1');
  });

  it('keeps an unknown attribute visible by its key rather than dropping the condition', () => {
    const summary = summariseCondition(
      {
        attribute_key: 'deleted_custom_attribute',
        filter_operator: 'equal_to',
        values: ['x'],
      },
      filterTypes
    );

    expect(summary).toBe('deleted_custom_attribute equal_to x');
  });

  it('omits the value entirely for an operator that takes none', () => {
    const summary = summariseCondition(
      {
        attribute_key: 'country_code',
        filter_operator: 'not_equal_to',
        values: [],
      },
      filterTypes
    );

    expect(summary).toBe('Country is not');
  });
});

describe('summariseAudience', () => {
  const query = {
    payload: [
      {
        attribute_key: 'country_code',
        filter_operator: 'equal_to',
        values: ['KW'],
        query_operator: 'and',
      },
      {
        attribute_key: 'commerce_orders_count',
        filter_operator: 'is_greater_than',
        values: [2],
      },
    ],
  };

  it('joins the conditions into one readable line', () => {
    expect(summariseAudience(query, filterTypes, { andLabel: 'and' })).toBe(
      'Country is Kuwait and Orders is greater than 2'
    );
  });

  it('is empty for an audience with no conditions, so a caller can fall back', () => {
    expect(summariseAudience({ payload: [] }, filterTypes)).toBe('');
    expect(summariseAudience(undefined, filterTypes)).toBe('');
  });

  it('stops at the limit and says how many conditions are left', () => {
    const summary = summariseAudience(query, filterTypes, {
      limit: 1,
      andLabel: 'and',
      moreLabel: count => `+${count} more`,
    });

    expect(summary).toBe('Country is Kuwait +1 more');
  });

  it('works without a vocabulary at all, falling back to the stored keys', () => {
    expect(summariseAudience(query, [], { andLabel: 'and' })).toBe(
      'country_code equal_to KW and commerce_orders_count is_greater_than 2'
    );
  });
});
