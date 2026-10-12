/**
 * THE SIDEBAR'S NAVIGATION CONTRACT, stated once.
 *
 * A sidebar entry reaches somewhere in exactly one of three ways, and this module is the only place that
 * says so:
 *
 *   `to`        a Vue router target. Permissions and feature flags are resolved against the target route's
 *               own meta (sidebar/provider.js `isAllowed`), so the ROUTE is the gate for both the nav entry
 *               and the direct URL.
 *   `href`      a destination outside the Vue router -- a server-rendered page, or a configured external
 *               link such as documentation or support. There is no route to resolve anything against, so it
 *               is visible to anyone who can see the group, and an empty value means "no link at all"
 *               (see `brandLink` in shared/composables/useBranding.js, which returns '' for a branded
 *               installation that configured none).
 *   `children`  a group, which reaches somewhere if any of its children do.
 *
 * WHY THIS EXISTS. `Sidebar.vue` used to end the Help and Support group with
 * `.filter(child => child.href)`. That was right for its two entries, both of which are href-only and may be
 * absent -- but as a rule it says "an entry without an href is not an entry", which is not the contract. A
 * `to`-based child added to that group later would have been dropped silently, with nothing to explain why,
 * and the only statement of the real rule lived in `SidebarGroup.vue` as a different expression. One rule,
 * one module, and `specs/navigationContract.spec.js` holds it.
 */

/**
 * Whether a value is a usable navigation target: a non-empty string. An empty `href` is how a branded
 * installation says it has no such link, so it is not a target.
 * @param {unknown} target - a `to` or `href` value
 * @returns {boolean}
 */
const isTarget = target => {
  if (typeof target === 'string') return target.trim().length > 0;

  // A router target may be a location object ({ name, params }).
  return Boolean(target);
};

/**
 * Whether this entry declares any routing form at all. It says nothing about whether the viewer is ALLOWED
 * there -- that is the route's meta, resolved by `SidebarGroup.vue`'s `isReachable`.
 * @param {object} entry - a sidebar entry
 * @returns {boolean}
 */
export const isNavigable = entry => {
  if (!entry) return false;
  if (Array.isArray(entry.children)) return entry.children.some(isNavigable);

  return isTarget(entry.to) || isTarget(entry.href);
};

/**
 * The entries of a group that declare a routing form. Use this instead of filtering on one form by hand, so
 * an entry using the other form cannot be dropped by accident.
 * @param {Array<object>} entries - sidebar entries
 * @returns {Array<object>} - the navigable ones, in order
 */
export const navigableEntries = (entries = []) => entries.filter(isNavigable);
