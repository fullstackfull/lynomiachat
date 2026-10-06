// Keeping a half-filled campaign while the user steps out to build an audience
// (docs/product-enablement/13-audience-ux-implementation.md).
//
// The journey this exists for: a campaign needs a shared audience, the account has none, so the user has to go to
// Contacts, build one, and come back. Before this, leaving the campaign page unmounted the form and discarded
// everything typed into it — the campaigns subtree is rendered by a bare `<router-view />`
// (`routes/dashboard/Dashboard.vue`), so its `keep-alive` does not survive a trip to Contacts.
//
// The carrier is `sessionStorage`, through the helper the dashboard already has. That is deliberately the smallest
// thing that works: a draft belongs to one tab and one sitting, it must not outlive a sign-out, and it is never
// shared with anyone. No table, no store module, no server state. A draft is read exactly once, by the page that
// saved it, and removed as it is read.

import SessionStorage from 'shared/helpers/sessionStorage';

const KEY_PREFIX = 'lynomia.campaignDraft';

// A draft is worthless once the sitting that produced it is over, and a stale one restoring over a fresh form is
// worse than no draft at all.
const MAX_AGE_MS = 60 * 60 * 1000;

const keyFor = campaignType => `${KEY_PREFIX}.${campaignType}`;

/**
 * Forgets a campaign draft. Called when the campaign is created and when the user closes the form deliberately —
 * in both cases they are finished with it.
 * @param {string} campaignType - Which campaign form.
 */
export const clearCampaignDraft = campaignType => {
  if (!campaignType) return;

  try {
    SessionStorage.remove(keyFor(campaignType));
  } catch {
    // As above: storage problems never surface to the user.
  }
};

/**
 * Remembers a campaign form's current values so the page can restore them when the user returns.
 * @param {string} campaignType - Which campaign form, e.g. 'whatsapp' or 'sms'.
 * @param {Object} state - The form's values. Stored as-is; keep it to plain data.
 * @param {number} savedAt - Epoch milliseconds, supplied by the caller so this module stays testable.
 */
export const saveCampaignDraft = (campaignType, state, savedAt) => {
  if (!campaignType || !state) return;

  try {
    SessionStorage.set(keyFor(campaignType), { savedAt, state });
  } catch {
    // Storage can be unavailable or full. A lost draft is a worse journey, never a broken page.
  }
};

/**
 * The draft for a campaign form, if there is a fresh one. Reading removes it: a draft is restored once, so
 * returning to the page later, or opening a second campaign, starts clean.
 * @param {string} campaignType - Which campaign form.
 * @param {number} now - Epoch milliseconds, supplied by the caller.
 * @returns {Object|null} The stored form values, or null when there is nothing usable.
 */
export const takeCampaignDraft = (campaignType, now) => {
  if (!campaignType) return null;

  let stored = null;
  try {
    stored = SessionStorage.get(keyFor(campaignType));
  } catch {
    return null;
  }
  clearCampaignDraft(campaignType);

  if (!stored?.state || typeof stored.savedAt !== 'number') return null;
  if (now - stored.savedAt > MAX_AGE_MS) return null;

  return stored.state;
};
