import {
  saveCampaignDraft,
  takeCampaignDraft,
  clearCampaignDraft,
} from '../campaignDraft';

const NOW = 1_700_000_000_000;

describe('campaignDraft', () => {
  beforeEach(() => {
    window.sessionStorage.clear();
  });

  it('gives back the values a form saved, so the user returns to what they typed', () => {
    saveCampaignDraft(
      'whatsapp',
      { title: 'Eid offer', inboxId: 7, audienceIds: [] },
      NOW
    );

    expect(takeCampaignDraft('whatsapp', NOW + 1000)).toEqual({
      title: 'Eid offer',
      inboxId: 7,
      audienceIds: [],
    });
  });

  it('restores a draft once, so a later visit starts on a clean form', () => {
    saveCampaignDraft('whatsapp', { title: 'Eid offer' }, NOW);

    expect(takeCampaignDraft('whatsapp', NOW)).toEqual({ title: 'Eid offer' });
    expect(takeCampaignDraft('whatsapp', NOW)).toBeNull();
  });

  it('keeps each campaign type to its own draft', () => {
    saveCampaignDraft('whatsapp', { title: 'On WhatsApp' }, NOW);
    saveCampaignDraft('sms', { title: 'On SMS' }, NOW);

    expect(takeCampaignDraft('sms', NOW)).toEqual({ title: 'On SMS' });
    expect(takeCampaignDraft('whatsapp', NOW)).toEqual({
      title: 'On WhatsApp',
    });
  });

  it('ignores a draft from an earlier sitting rather than restoring it over a fresh form', () => {
    saveCampaignDraft('whatsapp', { title: 'Yesterday' }, NOW);

    expect(takeCampaignDraft('whatsapp', NOW + 2 * 60 * 60 * 1000)).toBeNull();
  });

  it('forgets a draft on request, which is what finishing or cancelling does', () => {
    saveCampaignDraft('whatsapp', { title: 'Eid offer' }, NOW);
    clearCampaignDraft('whatsapp');

    expect(takeCampaignDraft('whatsapp', NOW)).toBeNull();
  });

  it('has nothing to give when nothing was saved', () => {
    expect(takeCampaignDraft('whatsapp', NOW)).toBeNull();
  });

  it('saves nothing without a campaign type or a state, instead of writing a useless entry', () => {
    saveCampaignDraft('', { title: 'x' }, NOW);
    saveCampaignDraft('whatsapp', null, NOW);

    expect(takeCampaignDraft('whatsapp', NOW)).toBeNull();
    expect(window.sessionStorage.length).toBe(0);
  });

  it('survives storage being unavailable, because a lost draft must never break the page', () => {
    const setItem = vi
      .spyOn(Storage.prototype, 'setItem')
      .mockImplementation(() => {
        throw new Error('QuotaExceededError');
      });

    expect(() =>
      saveCampaignDraft('whatsapp', { title: 'x' }, NOW)
    ).not.toThrow();

    setItem.mockRestore();
  });

  it('ignores a stored entry that is not a draft', () => {
    window.sessionStorage.setItem(
      'lynomia.campaignDraft.whatsapp',
      '{"nope":1}'
    );

    expect(takeCampaignDraft('whatsapp', NOW)).toBeNull();
  });
});
