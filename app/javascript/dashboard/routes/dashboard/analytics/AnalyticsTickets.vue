<script setup>
import AnalyticsAPI from 'dashboard/api/analytics';
import AnalyticsScreen from 'dashboard/components-next/analytics/AnalyticsScreen.vue';
import { TICKET_BREAKDOWN_DIMENSIONS } from 'dashboard/constants/analytics';

// Arrived, closed, missed: whether the team is keeping up, and how often a target went past. No attainment
// percentage, by design -- every SLA figure begins when a policy is attached to a case, so a rate over a range
// that predates the policy would divide two different populations (docs/p9/02-support-tickets.md §analytics).
const SERIES_CARDS = [
  { key: 'tickets_created', color: 'rgb(var(--blue-9))' },
  { key: 'tickets_resolved', color: 'rgb(var(--teal-9))' },
  { key: 'resolution_breaches', color: 'rgb(var(--ruby-9))' },
];

const fetcher = (params, options) => AnalyticsAPI.getTickets(params, options);
</script>

<template>
  <AnalyticsScreen
    scope="TICKETS"
    :fetcher="fetcher"
    :series-cards="SERIES_CARDS"
    :breakdown-dimensions="TICKET_BREAKDOWN_DIMENSIONS"
  />
</template>
