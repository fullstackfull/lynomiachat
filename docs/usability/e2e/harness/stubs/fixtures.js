// The account the journeys run against: a WooCommerce store, two currencies, three teams, one label, one shared
// audience referenced by a rule and a scheduled campaign, and one personal filter.
export const FIXTURES = {
  accountId: 1,
  teams: [
    { id: 1, name: 'Customer Care' },
    { id: 2, name: 'Orders' },
    { id: 3, name: 'Products' },
  ],
  labels: [{ id: 1, title: 'vip' }],
  contactViews: [
    {
      id: 7,
      name: 'VIP buyers',
      shared: true,
      query: {
        payload: [
          {
            attribute_key: 'commerce_spend_sar',
            filter_operator: 'is_greater_than',
            attribute_model: 'commerce',
            values: ['1000'],
            query_operator: null,
          },
        ],
      },
      active_automation_rules_count: 2,
      campaigns_count: 1,
    },
    { id: 8, name: 'My drafts', shared: false, query: { payload: [] } },
  ],
  whatsAppInboxes: [{ id: 5, name: 'WhatsApp' }],
  stores: [{ id: 4, name: 'Syria Cosmetics', provider: 'woocommerce' }],
  currencies: ['SAR', 'AED'],
};
