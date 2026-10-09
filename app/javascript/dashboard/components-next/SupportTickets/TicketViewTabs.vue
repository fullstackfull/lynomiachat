<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import { TICKET_VIEWS } from 'dashboard/constants/supportTickets';

// The workspace's saved views. Each tab is labelled with the figure the list response already carries for it,
// so a tab can never show a number the list below it disagrees with -- and six tabs cost one request, not six.
const props = defineProps({
  view: {
    type: String,
    required: true,
  },
  // `meta.counts` from the list response.
  counts: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['change']);

const { t } = useI18n();

const tabs = computed(() =>
  TICKET_VIEWS.map(view => ({
    value: view.key,
    label: t(`SUPPORT_TICKETS.VIEWS.${view.key.toUpperCase()}`),
    count: Number(props.counts[view.countKey]) || 0,
  }))
);

const activeIndex = computed(() =>
  Math.max(
    tabs.value.findIndex(tab => tab.value === props.view),
    0
  )
);
</script>

<template>
  <TabBar
    :tabs="tabs"
    :initial-active-tab="activeIndex"
    @tab-changed="tab => emit('change', tab.value)"
  />
</template>
