import { ref, computed, shallowRef } from 'vue';
import ContactActivityAPI from 'dashboard/api/contactActivity';
import { useAbortableRequest } from './useAbortableRequest';
import {
  CONTACT_ACTIVITY_CATEGORIES,
  CONTACT_ACTIVITY_PAGE_SIZE,
} from 'dashboard/constants/contactActivity';

/**
 * Cursor paging for one contact's activity timeline
 * (docs/p8/03-contact-activity-timeline.md).
 *
 * Entries accumulate: "load more" appends the next page rather than replacing
 * the list, because a timeline is read downwards. Changing the category filter
 * starts a new list, because it is a different question.
 *
 * Requests go through the shared abortable-request helper, so switching filters
 * quickly cannot let a slow earlier response append rows the viewer no longer
 * asked for.
 *
 * @param {import('vue').Ref<string|number>} contactId
 * @returns {object} entries, filter state and load controls
 */
export function useContactActivity(contactId) {
  const { run, isPending } = useAbortableRequest();

  const entries = shallowRef([]);
  const category = ref(CONTACT_ACTIVITY_CATEGORIES.ALL);
  const nextCursor = ref(null);
  const warnings = shallowRef([]);
  const error = ref(null);
  const hasLoadedOnce = ref(false);

  const isPartial = computed(() => warnings.value.length > 0);
  const hasMore = computed(() => Boolean(nextCursor.value));
  const isEmpty = computed(
    () => hasLoadedOnce.value && !error.value && entries.value.length === 0
  );

  const requestParams = cursor => ({
    // `all` is the absence of a filter, not a category the server knows.
    categories:
      category.value === CONTACT_ACTIVITY_CATEGORIES.ALL
        ? undefined
        : [category.value],
    cursor,
    limit: CONTACT_ACTIVITY_PAGE_SIZE,
  });

  const fetchPage = async ({ append }) => {
    error.value = null;
    try {
      const response = await run(
        signal =>
          ContactActivityAPI.get(
            contactId.value,
            requestParams(append ? nextCursor.value : undefined),
            { signal }
          ),
        { onAbort: null }
      );
      if (response === null) return;

      const payload = response.data.payload || [];
      entries.value = append ? [...entries.value, ...payload] : payload;
      nextCursor.value = response.data.meta?.next_cursor || null;
      warnings.value = response.data.meta?.warnings || [];
      hasLoadedOnce.value = true;
    } catch (requestError) {
      error.value = requestError;
    }
  };

  const load = () => fetchPage({ append: false });

  const loadMore = () => {
    if (!nextCursor.value) return Promise.resolve();
    return fetchPage({ append: true });
  };

  const setCategory = value => {
    category.value = value;
    nextCursor.value = null;
    return load();
  };

  return {
    entries,
    category,
    warnings,
    error,
    isLoading: isPending,
    hasLoadedOnce,
    isPartial,
    hasMore,
    isEmpty,
    load,
    loadMore,
    setCategory,
  };
}
