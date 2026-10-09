<script setup>
import AnalyticsAPI from 'dashboard/api/analytics';
import AnalyticsScreen from 'dashboard/components-next/analytics/AnalyticsScreen.vue';
import { AUTOMATION_BREAKDOWN_DIMENSIONS } from 'dashboard/constants/analytics';

// Armed against acted against declined: the three lines that separate "fewer rules fired" from "the same rules
// fired and declined more often".
const SERIES_CARDS = [
  { key: 'episodes_armed', color: 'rgb(var(--blue-9))' },
  { key: 'executed', color: 'rgb(var(--teal-9))' },
  { key: 'skipped', color: 'rgb(var(--amber-9))' },
];

const fetcher = (params, options) =>
  AnalyticsAPI.getAutomations(params, options);
</script>

<template>
  <AnalyticsScreen
    scope="AUTOMATIONS"
    :fetcher="fetcher"
    :series-cards="SERIES_CARDS"
    :breakdown-dimensions="AUTOMATION_BREAKDOWN_DIMENSIONS"
  />
</template>
