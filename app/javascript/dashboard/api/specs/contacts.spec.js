import contactAPI, {
  buildContactParams,
  buildImportFormData,
} from '../contacts';
import ApiClient from '../ApiClient';

describe('#ContactsAPI', () => {
  it('creates correct instance', () => {
    expect(contactAPI).toBeInstanceOf(ApiClient);
    expect(contactAPI).toHaveProperty('get');
    expect(contactAPI).toHaveProperty('show');
    expect(contactAPI).toHaveProperty('create');
    expect(contactAPI).toHaveProperty('update');
    expect(contactAPI).toHaveProperty('delete');
    expect(contactAPI).toHaveProperty('getConversations');
    expect(contactAPI).toHaveProperty('filter');
    expect(contactAPI).toHaveProperty('destroyAvatar');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#get', () => {
      contactAPI.get(1, 'name', 'customer-support');
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/contacts', {
        params: {
          include_contact_inboxes: false,
          page: 1,
          sort: 'name',
          labels: ['customer-support'],
        },
      });
    });

    it('#getConversations', () => {
      contactAPI.getConversations(1);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/contacts/1/conversations',
        { params: {} }
      );
    });

    it('#getContactableInboxes', () => {
      contactAPI.getContactableInboxes(1);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/contacts/1/contactable_inboxes'
      );
    });

    it('#getContactLabels', () => {
      contactAPI.getContactLabels(1);
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/contacts/1/labels');
    });

    it('#updateContactLabels', () => {
      const labels = ['support-query'];
      contactAPI.updateContactLabels(1, labels);
      expect(axiosMock.post).toHaveBeenCalledWith('/api/v1/contacts/1/labels', {
        labels,
      });
    });

    it('#search', () => {
      contactAPI.search('leads', 1, 'date', 'customer-support');
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/contacts/search', {
        params: {
          include_contact_inboxes: false,
          page: 1,
          sort: 'date',
          q: 'leads',
          labels: ['customer-support'],
        },
        signal: undefined,
      });
    });

    it('#search with signal', () => {
      const controller = new AbortController();
      contactAPI.search('leads', 1, 'date', 'customer-support', {
        signal: controller.signal,
      });
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/contacts/search', {
        params: {
          include_contact_inboxes: false,
          page: 1,
          sort: 'date',
          q: 'leads',
          labels: ['customer-support'],
        },
        signal: controller.signal,
      });
    });

    it('#search passes the term as a param so it is encoded', () => {
      contactAPI.search('jane+shop@gmail.com');
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/contacts/search', {
        params: {
          include_contact_inboxes: false,
          page: 1,
          sort: 'name',
          q: 'jane+shop@gmail.com',
        },
        signal: undefined,
      });
    });

    it('#destroyCustomAttributes', () => {
      contactAPI.destroyCustomAttributes(1, ['cloudCustomer']);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/contacts/1/destroy_custom_attributes',
        {
          custom_attributes: ['cloudCustomer'],
        }
      );
    });

    it('#importContacts', () => {
      const file = 'file';
      contactAPI.importContacts(file);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/contacts/import',
        expect.any(FormData),
        {
          headers: { 'Content-Type': 'multipart/form-data' },
        }
      );
    });

    it('#filter', () => {
      const queryPayload = {
        payload: [
          {
            attribute_key: 'email',
            filter_operator: 'contains',
            values: ['fayaz'],
            query_operator: null,
          },
        ],
      };
      contactAPI.filter(1, 'name', queryPayload);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/contacts/filter',
        queryPayload,
        {
          params: { include_contact_inboxes: false, page: 1, sort: 'name' },
        }
      );
    });

    it('#destroyAvatar', () => {
      contactAPI.destroyAvatar(1);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/contacts/1/avatar'
      );
    });
  });
});

describe('#buildContactParams', () => {
  it('returns correct params', () => {
    expect(buildContactParams(1, 'name', '', '')).toEqual({
      include_contact_inboxes: false,
      page: 1,
      sort: 'name',
    });
    expect(buildContactParams(1, 'name', 'customer-support', '')).toEqual({
      include_contact_inboxes: false,
      page: 1,
      sort: 'name',
      labels: ['customer-support'],
    });
    expect(
      buildContactParams(1, 'name', 'customer-support', 'message-content')
    ).toEqual({
      include_contact_inboxes: false,
      page: 1,
      sort: 'name',
      q: 'message-content',
      labels: ['customer-support'],
    });
  });

  describe('buildImportFormData', () => {
    const entries = formData => [...formData.entries()];

    it('sends a file when one was chosen', () => {
      const file = new File(['a,b'], 'contacts.csv', { type: 'text/csv' });

      expect(entries(buildImportFormData({ file }))).toEqual([
        ['import_file', file],
      ]);
    });

    it('sends pasted numbers when no file was chosen', () => {
      expect(
        entries(buildImportFormData({ phoneNumbers: '+96551112233' }))
      ).toEqual([['phone_numbers', '+96551112233']]);
    });

    it('prefers the file, so the two sources never arrive together', () => {
      const file = new File(['a,b'], 'contacts.csv', { type: 'text/csv' });
      const keys = entries(
        buildImportFormData({ file, phoneNumbers: '+96551112233' })
      ).map(([key]) => key);

      expect(keys).toEqual(['import_file']);
    });

    // The point of the id: the preview already stored those bytes, so sending the file again is the whole
    // transfer repeated for nothing (docs/contacts/10-phase-d.md).
    it('sends the stored file in place of the file itself', () => {
      const file = new File(['a,b'], 'contacts.csv', { type: 'text/csv' });

      expect(
        entries(buildImportFormData({ file, importFileBlobId: 'signed-id' }))
      ).toEqual([['import_file_blob_id', 'signed-id']]);
    });

    it('sends the file again once the stored copy is gone', () => {
      const file = new File(['a,b'], 'contacts.csv', { type: 'text/csv' });

      expect(
        entries(buildImportFormData({ file, importFileBlobId: '' }))
      ).toEqual([['import_file', file]]);
    });

    it('sends each label separately, so Rails reads an array', () => {
      expect(
        entries(
          buildImportFormData({
            phoneNumbers: '+96551112233',
            labels: ['vip', 'wholesale'],
          })
        )
      ).toEqual([
        ['phone_numbers', '+96551112233'],
        ['labels[]', 'vip'],
        ['labels[]', 'wholesale'],
      ]);
    });

    it('leaves out the choices nobody made, so the server applies its own defaults', () => {
      const keys = entries(
        buildImportFormData({ phoneNumbers: '+96551112233' })
      ).map(([key]) => key);

      expect(keys).not.toContain('default_country');
      expect(keys).not.toContain('duplicate_policy');
    });

    it('sends the choices that were made', () => {
      expect(
        entries(
          buildImportFormData({
            phoneNumbers: '+96551112233',
            defaultCountry: 'SA',
            duplicatePolicy: 'keep',
          })
        )
      ).toEqual([
        ['phone_numbers', '+96551112233'],
        ['default_country', 'SA'],
        ['duplicate_policy', 'keep'],
      ]);
    });
  });
});
