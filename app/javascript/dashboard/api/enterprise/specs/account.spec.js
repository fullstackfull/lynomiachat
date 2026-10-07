import accountAPI from '../account';
import ApiClient from '../../ApiClient';

// Only Captain's usage quota is left here; Lynomia bills through its own API, so the cloud billing and
// account self-deletion endpoints are gone.
describe('#enterpriseAccountAPI', () => {
  it('creates correct instance', () => {
    expect(accountAPI).toBeInstanceOf(ApiClient);
    expect(accountAPI).toHaveProperty('get');
    expect(accountAPI).toHaveProperty('show');
    expect(accountAPI).toHaveProperty('create');
    expect(accountAPI).toHaveProperty('update');
    expect(accountAPI).toHaveProperty('delete');
    expect(accountAPI).toHaveProperty('getLimits');
    expect(accountAPI).not.toHaveProperty('checkout');
    expect(accountAPI).not.toHaveProperty('billingSummary');
    expect(accountAPI).not.toHaveProperty('toggleDeletion');
    expect(accountAPI).not.toHaveProperty('createTopupCheckout');
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

    it('#getLimits', () => {
      accountAPI.getLimits();
      expect(axiosMock.get).toHaveBeenCalledWith('/enterprise/api/v1/limits');
    });
  });
});
