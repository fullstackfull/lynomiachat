<script setup>
import AnalyticsAPI from 'dashboard/api/analytics';
import AnalyticsScreen from 'dashboard/components-next/analytics/AnalyticsScreen.vue';
import { ANALYTICS_BREAKDOWN_DIMENSIONS } from 'dashboard/constants/analytics';

// Each series answers one operational question, which is why there are four and not one per available metric:
// how much arrived, how much closed, and the two message directions that show whether the team is replying.
const SERIES_CARDS = [
  { key: 'conversations_created', color: 'rgb(var(--blue-9))' },
  { key: 'conversations_resolved', color: 'rgb(var(--teal-9))' },
  { key: 'inbound_messages', color: 'rgb(var(--iris-9))' },
  { key: 'outbound_messages', color: 'rgb(var(--amber-9))' },
];

const fetcher = (params, options) => AnalyticsAPI.getOverview(params, options);
</script>

<template>
  <AnalyticsScreen
    scope="CONVERSATIONS"
    :fetcher="fetcher"
    :series-cards="SERIES_CARDS"
    :breakdown-dimensions="ANALYTICS_BREAKDOWN_DIMENSIONS"
  />
</template>
