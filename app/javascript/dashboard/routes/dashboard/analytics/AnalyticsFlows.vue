<script setup>
import AnalyticsAPI from 'dashboard/api/analytics';
import AnalyticsScreen from 'dashboard/components-next/analytics/AnalyticsScreen.vue';
import { FLOW_BREAKDOWN_DIMENSIONS } from 'dashboard/constants/analytics';

const SERIES_CARDS = [
  { key: 'sessions_started', color: 'rgb(var(--blue-9))' },
  { key: 'sessions_completed', color: 'rgb(var(--teal-9))' },
  { key: 'sessions_failed', color: 'rgb(var(--ruby-9))' },
];

const fetcher = (params, options) => AnalyticsAPI.getFlows(params, options);
</script>

<template>
  <AnalyticsScreen
    scope="FLOWS"
    :fetcher="fetcher"
    :series-cards="SERIES_CARDS"
    :breakdown-dimensions="FLOW_BREAKDOWN_DIMENSIONS"
  />
</template>
