import { createRouter, createMemoryHistory } from 'vue-router';
import { routes } from '../routes';

// The audiences destination is a static path that sits beside `contacts/:contactId`. If it ever lost that race it
// would silently open a contact whose id is the word "audiences", so the resolution is asserted rather than assumed.
const router = createRouter({ history: createMemoryHistory(), routes });

describe('contacts routes', () => {
  it('resolves the audiences destination to its own page, not to a contact', () => {
    const resolved = router.resolve('/app/accounts/1/contacts/audiences');

    expect(resolved.name).toBe('contacts_dashboard_audiences_index');
    expect(resolved.params.contactId).toBeUndefined();
  });

  it('still resolves a contact by id', () => {
    expect(router.resolve('/app/accounts/1/contacts/42').name).toBe(
      'contacts_edit'
    );
  });

  it('keeps the audiences destination behind the same feature flag and roles as the rest of Contacts', () => {
    const { meta } = router.resolve({
      name: 'contacts_dashboard_audiences_index',
      params: { accountId: 1 },
    });

    expect(meta.featureFlag).toBe('crm');
    expect(meta.permissions).toEqual([
      'administrator',
      'agent',
      'contact_manage',
    ]);
  });

  it('still resolves the list, segment, label and active views', () => {
    expect(router.resolve('/app/accounts/1/contacts').name).toBe(
      'contacts_dashboard_index'
    );
    expect(router.resolve('/app/accounts/1/contacts/segments/7').name).toBe(
      'contacts_dashboard_segments_index'
    );
    expect(router.resolve('/app/accounts/1/contacts/labels/vip').name).toBe(
      'contacts_dashboard_labels_index'
    );
    expect(router.resolve('/app/accounts/1/contacts/active').name).toBe(
      'contacts_dashboard_active'
    );
  });
});
