export const CAMPAIGN_TYPES = {
  ONGOING: 'ongoing',
  ONE_OFF: 'one_off',
};

// Entry types of a one-off campaign's audience: labels, and Lynomia shared audiences (docs/campaigns/02-recipients.md).
export const CAMPAIGN_AUDIENCE_TYPES = {
  LABEL: 'Label',
  AUDIENCE: 'Audience',
};

export const buildCampaignAudience = (labelIds = [], audienceIds = []) => [
  ...labelIds.map(id => ({ id, type: CAMPAIGN_AUDIENCE_TYPES.LABEL })),
  ...audienceIds.map(id => ({ id, type: CAMPAIGN_AUDIENCE_TYPES.AUDIENCE })),
];
