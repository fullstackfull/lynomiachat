<script setup>
import AnalyticsAPI from 'dashboard/api/analytics';
import AnalyticsScreen from 'dashboard/components-next/analytics/AnalyticsScreen.vue';
import { CAMPAIGN_BREAKDOWN_DIMENSIONS } from 'dashboard/constants/analytics';

const SERIES_CARDS = [
  { key: 'recipients_targeted', color: 'rgb(var(--blue-9))' },
  { key: 'delivered', color: 'rgb(var(--teal-9))' },
  { key: 'failed', color: 'rgb(var(--ruby-9))' },
];

const fetcher = (params, options) => AnalyticsAPI.getCampaigns(params, options);
</script>

<template>
  <AnalyticsScreen
    scope="CAMPAIGNS"
    :fetcher="fetcher"
    :series-cards="SERIES_CARDS"
    :breakdown-dimensions="CAMPAIGN_BREAKDOWN_DIMENSIONS"
  />
</template>
