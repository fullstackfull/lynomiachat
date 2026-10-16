/* global axios */

// THE PLAN A VISITOR CHOSE ON THE PUBLIC PRICING PAGE, read back once they have signed in.
//
// NOT account-scoped: it is asked before an account is chosen, because answering "which workspace should
// pay for this?" is half of what it returns. That is why this does not extend ApiClient, whose url builder
// assumes an account.
//
// The plan id lives in the Rails session, written by the marketing site
// (custom/app/controllers/marketing/plan_selections_controller.rb). The session cookie rides along with
// this request because the marketing site and the dashboard are the same origin; nothing is passed through
// the URL, so there is nothing for a caller to forge.
export default {
  get() {
    return axios.get('/api/v1/billing/pending_plan');
  },

  // Called once the dashboard has taken the person to the plan, or when they abandon it. Separate from the
  // read so that a page refresh mid-resume does not lose the intention.
  clear() {
    return axios.delete('/api/v1/billing/pending_plan');
  },
};
