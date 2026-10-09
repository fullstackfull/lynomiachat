<script setup>
import AnalyticsAPI from 'dashboard/api/analytics';
import AnalyticsScreen from 'dashboard/components-next/analytics/AnalyticsScreen.vue';
import { COMMERCE_BREAKDOWN_DIMENSIONS } from 'dashboard/constants/analytics';

// Abandoned, messaged, completed: the three lines that show whether outreach is keeping up with abandonment and
// what follows it. No money series exists, by design (docs/p8/02d-commerce-analytics.md).
const SERIES_CARDS = [
  { key: 'carts_abandoned', color: 'rgb(var(--amber-9))' },
  { key: 'carts_targeted', color: 'rgb(var(--blue-9))' },
  { key: 'carts_completed', color: 'rgb(var(--teal-9))' },
];

const fetcher = (params, options) => AnalyticsAPI.getCommerce(params, options);
</script>

<template>
  <AnalyticsScreen
    scope="COMMERCE"
    :fetcher="fetcher"
    :series-cards="SERIES_CARDS"
    :breakdown-dimensions="COMMERCE_BREAKDOWN_DIMENSIONS"
  />
</template>
