import {
  AVAILABLE_CUSTOM_ROLE_PERMISSIONS,
  PORTAL_PERMISSIONS,
} from '../permissions';

describe('custom role permissions', () => {
  // Lynomia publishes the documentation, so there is no workspace knowledge base. Offering the permission would
  // let an administrator grant something that cannot do anything: every portal, category and article policy
  // refuses a workspace request (custom/app/policies/custom/portal_policy.rb).
  it('does not offer a permission that grants nothing', () => {
    expect(AVAILABLE_CUSTOM_ROLE_PERMISSIONS).not.toContain(
      'knowledge_base_manage'
    );
  });

  it('still offers every permission that does grant something', () => {
    expect(AVAILABLE_CUSTOM_ROLE_PERMISSIONS).toEqual([
      'conversation_manage',
      'conversation_unassigned_manage',
      'conversation_participating_manage',
      'contact_manage',
      'report_manage',
      'commerce_order_manage',
      'support_ticket_manage',
    ]);
  });

  // The constant itself stays. A role created before the change still carries the permission on its record, and
  // global search uses it to decide who sees the read-only Articles tab -- the one way such a workspace can still
  // find the pages it published.
  it('keeps the name, because records created before the change still carry it', () => {
    expect(PORTAL_PERMISSIONS).toBe('knowledge_base_manage');
  });
});
