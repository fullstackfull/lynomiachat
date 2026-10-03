const ENABLED = [
  'crm',
  'lynomia_commerce',
  'lynomia_flow_builder',
  'automations',
  'whatsapp_campaigns',
  'campaigns',
  'api_and_webhooks',
];

export const useAccount = () => ({
  accountId: { value: 1 },
  isCloudFeatureEnabled: flag => ENABLED.includes(flag),
  accountScopedRoute: name => ({ name }),
  isOnChatwootCloud: false,
});
