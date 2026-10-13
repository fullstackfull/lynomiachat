// The route declaration IS the gate. The sidebar resolves permissions and feature flags against the target
// route's own meta (sidebar/provider.js `isAllowed`), so these three facts decide both whether the navigation
// entry appears and whether the direct URL is allowed:
//
//   - all three roles, because every member may open a ticket with Lynomia;
//   - no feature flag, ever, because the desk is never gated and never sold;
//   - `new` declared BEFORE `:ticketId`, or the create form is swallowed as a ticket id.
//
// The page components are stubbed: the route module imports them, and they reach the design system and the
// store. This file is about the declaration.
vi.mock('../pages/PlatformSupportRouteView.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../pages/PlatformSupportIndexPage.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../pages/PlatformSupportNewPage.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('../pages/PlatformSupportDetailPage.vue', () => ({
  default: { template: '<div />' },
}));

const { default: helpRoutes } = await import('../help.routes');

const parent = helpRoutes.routes[0];
const children = parent.children;

describe('the Platform Support tenant routes', () => {
  it('live under help/, never beside the tenant desk at support/cases', () => {
    expect(parent.path).toBe('/app/accounts/:accountId/help/tickets');
    expect(parent.path).not.toContain('/support/');
  });

  it('take the three names the contract reserves', () => {
    expect(children.map(child => child.name)).toEqual([
      'platform_support_tickets_index',
      'platform_support_tickets_new',
      'platform_support_tickets_show',
    ]);
  });

  it('declares new BEFORE :ticketId, so the create form is reachable', () => {
    const paths = children.map(child => child.path);

    expect(paths.indexOf('new')).toBeLessThan(paths.indexOf(':ticketId'));
  });

  it('admits an administrator, an agent and a custom-role holder', () => {
    children.forEach(child => {
      expect(child.meta.permissions).toEqual([
        'administrator',
        'agent',
        'custom_role',
      ]);
    });
  });

  it('carries no feature flag on any of the three', () => {
    children.forEach(child => {
      expect(child.meta.featureFlag).toBeUndefined();
    });
  });
});
