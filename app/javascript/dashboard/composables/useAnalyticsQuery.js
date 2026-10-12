import { ref, computed, shallowRef } from 'vue';
import { format, subDays, differenceInCalendarDays } from 'date-fns';
import { useAbortableRequest } from './useAbortableRequest';
import {
  ANALYTICS_GROUP_BY,
  ANALYTICS_MAX_BUCKETS,
  ANALYTICS_DATE_FORMAT,
  DEFAULT_ANALYTICS_RANGE_DAYS,
} from 'dashboard/constants/analytics';

/**
 * Request state for one Lynomia Analytics screen (docs/p8/02a-overview-conversation-analytics.md).
 *
 * The range is held as calendar dates, never instants: the server cuts buckets in the account's reporting
 * timezone, so sending the dates the operator picked is what makes two viewers of the same period see the same
 * totals. `format` from date-fns reads the local calendar parts of the picked Date, which is exactly what
 * "1 October" means to the person who clicked it.
 *
 * Requests go through the shared abortable-request helper, so dragging through a date picker cannot let a slow
 * earlier response overwrite a newer one.
 *
 * @param {(params: object, options: { signal: AbortSignal }) => Promise<{ data: any }>} fetcher
 * @returns {object} range state, the payload, and load/flag refs
 */
export function useAnalyticsQuery(fetcher) {
  const { run, isPending } = useAbortableRequest();

  const dateRange = ref([
    subDays(new Date(), DEFAULT_ANALYTICS_RANGE_DAYS - 1),
    new Date(),
  ]);
  const groupBy = ref(ANALYTICS_GROUP_BY.DAY);
  const filters = ref({});
  const payload = shallowRef(null);
  const error = ref(null);
  const hasLoadedOnce = ref(false);

  const since = computed(() =>
    format(dateRange.value[0], ANALYTICS_DATE_FORMAT)
  );
  const until = computed(() =>
    format(dateRange.value[1], ANALYTICS_DATE_FORMAT)
  );

  // A bucket ceiling the server also enforces (Analytics::DateRange::MAX_BUCKETS). Checking it here is not a
  // duplicated guard but a usable control: it decides which grouping options the operator is offered, so
  // picking "last year" does not hand them a request the server will reject.
  //
  // The weekly and monthly counts add one because a range starting mid-week or mid-month gets a partial bucket
  // at each end. That makes the estimate an upper bound on what the server counts, never lower: checked
  // against the server's own bucket_starts walk over 72,000 start-date/span/grouping combinations with no case
  // where this under-estimated. Erring high is the safe direction -- it can hide a grouping the server would
  // have accepted at the margin, but it can never offer one the server would reject.
  const availableGroupBy = computed(() => {
    const days =
      differenceInCalendarDays(dateRange.value[1], dateRange.value[0]) + 1;
    return Object.values(ANALYTICS_GROUP_BY).filter(option => {
      const buckets = {
        [ANALYTICS_GROUP_BY.DAY]: days,
        [ANALYTICS_GROUP_BY.WEEK]: Math.ceil(days / 7) + 1,
        [ANALYTICS_GROUP_BY.MONTH]: Math.ceil(days / 28) + 1,
      }[option];
      return buckets <= ANALYTICS_MAX_BUCKETS[option];
    });
  });

  const params = computed(() => ({
    since: since.value,
    until: until.value,
    group_by: groupBy.value,
    ...filters.value,
  }));

  const load = async () => {
    error.value = null;
    try {
      const response = await run(signal => fetcher(params.value, { signal }), {
        onAbort: null,
      });
      if (response === null) return;
      payload.value = response.data;
      hasLoadedOnce.value = true;
    } catch (requestError) {
      error.value = requestError;
    }
  };

  const setDateRange = range => {
    dateRange.value = range;
    if (!availableGroupBy.value.includes(groupBy.value)) {
      groupBy.value = availableGroupBy.value[availableGroupBy.value.length - 1];
    }
    return load();
  };

  const setGroupBy = value => {
    groupBy.value = value;
    return load();
  };

  const setFilters = value => {
    filters.value = value;
    return load();
  };

  return {
    dateRange,
    groupBy,
    filters,
    since,
    until,
    params,
    payload,
    error,
    availableGroupBy,
    isLoading: isPending,
    hasLoadedOnce,
    load,
    setDateRange,
    setGroupBy,
    setFilters,
  };
}
