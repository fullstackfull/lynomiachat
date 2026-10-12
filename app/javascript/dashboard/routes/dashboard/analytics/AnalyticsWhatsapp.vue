<script setup>
import AnalyticsAPI from 'dashboard/api/analytics';
import AnalyticsScreen from 'dashboard/components-next/analytics/AnalyticsScreen.vue';
import { WHATSAPP_BREAKDOWN_DIMENSIONS } from 'dashboard/constants/analytics';

// Sent, arrived, refused: the three lines that show whether a drop in delivery is a drop in volume or a rise in
// refusals. A read series is deliberately absent -- read is a customer behaviour, not a delivery outcome, and the
// read rate card already carries it.
const SERIES_CARDS = [
  { key: 'messages_sent', color: 'rgb(var(--blue-9))' },
  { key: 'delivered', color: 'rgb(var(--teal-9))' },
  { key: 'failed', color: 'rgb(var(--ruby-9))' },
];

const fetcher = (params, options) => AnalyticsAPI.getWhatsapp(params, options);
</script>

<template>
  <AnalyticsScreen
    scope="WHATSAPP"
    :fetcher="fetcher"
    :series-cards="SERIES_CARDS"
    :breakdown-dimensions="WHATSAPP_BREAKDOWN_DIMENSIONS"
  />
</template>
