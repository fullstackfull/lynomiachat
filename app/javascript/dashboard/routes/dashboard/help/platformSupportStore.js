import { computed, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import PlatformSupportAPI from './platformSupportApi';

/**
 * The Platform Support Desk's own unread count, and the only state this module shares between screens.
 *
 * WHY ITS OWN STORE AND NOT `notifications`.
 * The sidebar badge is DERIVED, not stored: the server computes `meta.counts.unread` from the ticket's own
 * three columns (`last_operator_message_at`, `customer_last_viewed_at`), so the badge is a count over an
 * indexed account scope and cannot drift from the thread the way a denormalized feed row can
 * (docs/platform-support/04-customer-ux.md §6). Reading it from the `notifications` module would make the
 * badge depend on a feed whose rows this surface does not own, and on a read-time narrowing built for
 * conversations.
 *
 * WHY A MODULE SINGLETON AND NOT A VUEX MODULE.
 * Registering a Vuex module means editing `store/index.js`, which this module does not own
 * (§8 file ownership). A module-level ref is the smaller change and the same thing the badge needs: one
 * number, one writer per screen, no mutations to name.
 *
 * ZERO IS NOT A BADGE. `SidebarUnreadBadge` renders nothing at 0, which is the intended behaviour: a permanent
 * "0" trains people to ignore the entry.
 */

const unreadCount = ref(0);

// The account the count belongs to. Switching accounts must not leave the previous account's number on screen
// for the moment before the first request answers.
const countedAccountId = ref(null);

let accountWatcherInstalled = false;

/**
 * Replaces the count from a list response's `meta.counts.unread`.
 *
 * Called by the screens that have just read the authoritative number, so the common case costs no extra
 * request: the list page already asks for it.
 * @param {number|string|undefined} value - `meta.counts.unread`
 * @param {number|string|undefined} accountId - the account that count was read for
 * @returns {void}
 */
export function setPlatformSupportUnreadCount(value, accountId) {
  const next = Number(value);
  unreadCount.value = Number.isFinite(next) && next > 0 ? next : 0;
  if (accountId !== undefined) countedAccountId.value = Number(accountId);
}

/**
 * Re-reads the count from the server for one account.
 *
 * Asks for the smallest possible page: the payload is discarded and only `meta.counts.unread` is kept, so this
 * is a count query and not a list fetch. A failure leaves the previous number alone rather than showing a
 * wrong one -- the badge is an invitation, not a fact somebody acts on.
 * @param {number|string} accountId - the account to count for
 * @returns {Promise<void>}
 */
export async function refreshPlatformSupportUnreadCount(accountId) {
  if (!accountId) return;

  try {
    const response = await PlatformSupportAPI.getTickets({ per_page: 1 });
    setPlatformSupportUnreadCount(
      response?.data?.meta?.counts?.unread,
      accountId
    );
  } catch {
    // Deliberately silent. The desk is reachable from its own sidebar entry whether or not this number
    // resolved, and a toast about a badge is noise.
  }
}

/**
 * The shared unread count, for the sidebar badge and for any screen that changes it.
 *
 * The first caller inside a component scope installs the account watcher, so the count follows the account
 * switcher without every call site remembering to. Later callers reuse the same state.
 * @returns {{unreadCount: import('vue').ComputedRef<number>, refresh: () => Promise<void>}}
 */
export function usePlatformSupportUnread() {
  const accountId = useMapGetter('getCurrentAccountId');

  if (!accountWatcherInstalled) {
    accountWatcherInstalled = true;
    watch(
      accountId,
      id => {
        if (Number(id) !== countedAccountId.value) unreadCount.value = 0;
        refreshPlatformSupportUnreadCount(id);
      },
      { immediate: true }
    );
  }

  return {
    unreadCount: computed(() => unreadCount.value),
    refresh: () => refreshPlatformSupportUnreadCount(accountId.value),
  };
}

/**
 * Resets the shared state. Exists for the specs, which share one module instance across examples.
 * @returns {void}
 */
export function resetPlatformSupportUnreadState() {
  unreadCount.value = 0;
  countedAccountId.value = null;
  accountWatcherInstalled = false;
}
