import campaigns from '../campaigns';
import ApiClient from '../ApiClient';
import { buildCampaignAudience } from 'shared/constants/campaign';

describe('#CampaignAPI', () => {
  it('creates correct instance', () => {
    expect(campaigns).toBeInstanceOf(ApiClient);
    expect(campaigns).toHaveProperty('get');
    expect(campaigns).toHaveProperty('show');
    expect(campaigns).toHaveProperty('create');
    expect(campaigns).toHaveProperty('update');
    expect(campaigns).toHaveProperty('delete');
  });

  describe('#audiencePreview', () => {
    const originalAxios = window.axios;
    const axiosMock = { post: vi.fn(() => Promise.resolve()) };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('posts label and shared audience references, never their contacts', () => {
      const signal = new AbortController().signal;
      const audience = buildCampaignAudience([3], [7, 8]);

      campaigns.audiencePreview(audience, { signal });

      expect(audience).toEqual([
        { id: 3, type: 'Label' },
        { id: 7, type: 'Audience' },
        { id: 8, type: 'Audience' },
      ]);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/campaigns/audience_preview',
        { audience },
        { signal }
      );
    });
  });
});
