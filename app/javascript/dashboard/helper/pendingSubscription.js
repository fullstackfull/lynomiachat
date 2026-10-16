import PendingPlanAPI from '../api/pendingPlan';
import { frontendURL } from './URLHelper';

// RESUMING A PURCHASE THAT STARTED ON THE PUBLIC SITE.
//
// A visitor picks a plan on /pricing, which records it in their Rails session and sends them to sign in.
// By the time they are back in the dashboard they may have created an account, confirmed an email address
// and walked through onboarding -- three steps that each destroy a query string, which is why the
// intention was never carried in the URL. This asks the server whether one is still waiting.
//
// IT NEVER BUYS ANYTHING. All it computes is a URL -- the subscription settings page of an account the
// person administers, with the plan preselected. The purchase is still a deliberate click away, through
// the authorized endpoints that re-check the account, the role and the plan.
//
// AT MOST ONE REDIRECT PER TAB, and the reason is measured rather than defensive. The destination page
// clears the intention once it has shown it (deliberately not at read time, so a refresh on the way
// through onboarding does not drop it), but that clear is a write to a COOKIE session, and the dashboard
// fires a dozen other requests while it is in flight. Any of them that loaded the session before the
// clear and responds after it writes the old session back, and the intention returns. Observed: with the
// dashboard booting, `DELETE /api/v1/billing/pending_plan` answers 204 and the next read still has the
// plan; issue the same call with nothing else in flight and the plan is gone. So the clear is best effort
// by nature, and a lost one must not be able to keep yanking somebody out of their inbox. `sessionStorage`
// is the right scope for "this tab has already been taken to its plan": it survives a reload, dies with
// the tab, and is never shared with another tab or device. A genuinely new visit within the server's
// one-hour window gets its redirect, as it should.
const RESUMED_KEY = 'pendingSubscriptionResumed';

let checked = false;

const alreadyResumed = () => {
  try {
    return sessionStorage.getItem(RESUMED_KEY) === '1';
  } catch {
    return false;
  }
};

const markResumed = () => {
  try {
    sessionStorage.setItem(RESUMED_KEY, '1');
  } catch {
    // Private browsing or blocked storage: the server-side clear is still in place, and the worst case is
    // one extra redirect to a page that names the plan the person chose.
  }
};

// Which workspace to land on when the person administers several. The one they were last in, if they
// administer it -- that is where they think they are -- and otherwise the first. Either way the
// destination page names the workspace and offers the others, because paying from the wrong one is an
// expensive mistake to make silently.
const landingAccount = (accounts, currentAccountId) =>
  accounts.find(account => account.id === Number(currentAccountId)) ||
  accounts[0];

// Returns a frontend URL to redirect to, or null. Never throws: a failure here must not be able to stop
// somebody reaching their inbox.
export const pendingSubscriptionTarget = async currentAccountId => {
  if (checked || alreadyResumed()) return null;
  checked = true;

  try {
    const { data } = await PendingPlanAPI.get();
    const { plan, accounts = [] } = data || {};

    // No plan pending, or no workspace this person administers -- an agent cannot buy, and offering them
    // a page that will refuse them is worse than doing nothing.
    if (!plan || !accounts.length) return null;

    const target = landingAccount(accounts, currentAccountId);
    markResumed();
    return frontendURL(
      `accounts/${target.id}/settings/subscription?plan=${plan.id}`
    );
  } catch {
    return null;
  }
};
