<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Label from 'dashboard/components-next/label/Label.vue';

const props = defineProps({
  status: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();

const STATUS_TONES = {
  queued: 'neutral',
  sent: 'info',
  delivered: 'success',
  read: 'read',
  failed: 'danger',
  skipped: 'warning',
};

const tone = computed(() => STATUS_TONES[props.status] || 'neutral');

// A status the server adds that this build does not know is shown verbatim rather than hidden or
// guessed at — the one deliberate passthrough in the delivery table.
const label = computed(() => {
  const key = `CAMPAIGN.WHATSAPP.ANALYTICS.STATUS.${props.status.toUpperCase()}`;
  return STATUS_TONES[props.status] ? t(key) : props.status;
});
</script>

<template>
  <Label compact variant="solid" :tone="tone" :label="label" />
</template>
