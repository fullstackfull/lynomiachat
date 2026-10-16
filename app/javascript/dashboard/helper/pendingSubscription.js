import PendingPlanAPI from '../api/pendingPlan';
import { frontendURL } from './URLHelper';

// RESUMING A PURCHASE THAT STARTED ON THE PUBLIC SITE.
//
// A visitor picks a plan on /pricing, which records it in their Rails session and sends them to sign in.
// By the time they are back in the dashboard they may have created an account, confirmed an email address
// and walked through onboarding -- three steps that each destroy a query string, which is why the
// intention was never carried in the URL. This asks the server whether one is still waiting.
//
// ASKED ONCE PER APP BOOT. `checked` makes this a one-shot: the route guard runs on every navigation and
// the answer is "no" for almost every person who ever loads the dashboard, so paying for it once per page
// load is the most it is worth. The endpoint costs a session read and no query when nothing is pending.
//
// IT NEVER BUYS ANYTHING. All it computes is a URL -- the subscription settings page of an account the
// person administers, with the plan preselected. The purchase is still a deliberate click away, through
// the authorized endpoints that re-check the account, the role and the plan. The intention is NOT cleared
// here either: the destination page clears it once it has shown it, so a refresh on the way does not
// silently drop it.
let checked = false;

export const resetPendingSubscriptionCheck = () => {
  checked = false;
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
  if (checked) return null;
  checked = true;

  try {
    const { data } = await PendingPlanAPI.get();
    const { plan, accounts = [] } = data || {};

    // No plan pending, or no workspace this person administers -- an agent cannot buy, and offering them
    // a page that will refuse them is worse than doing nothing.
    if (!plan || !accounts.length) return null;

    const target = landingAccount(accounts, currentAccountId);
    return frontendURL(
      `accounts/${target.id}/settings/subscription?plan=${plan.id}`
    );
  } catch {
    return null;
  }
};
