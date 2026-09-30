// Lynomia: the Lynomia Meta app requests only these Page scopes
// (no pages_read_engagement, no Instagram scopes) for connect and reauthorize.
export const FACEBOOK_PAGE_SCOPES = [
  'pages_manage_metadata',
  'business_management',
  'pages_messaging',
  'pages_show_list',
];

export const INSTAGRAM_SCOPES = [
  'instagram_basic',
  'instagram_manage_messages',
];

export const buildFacebookLoginScopes = ({
  includeInstagramScopes = false,
} = {}) => {
  const scopes = [...FACEBOOK_PAGE_SCOPES];
  if (includeInstagramScopes) {
    scopes.push(...INSTAGRAM_SCOPES);
  }
  return scopes.join(',');
};
