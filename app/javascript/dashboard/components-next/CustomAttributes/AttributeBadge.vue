<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'resolution',
    validator: value => ['pre-chat', 'resolution'].includes(value),
  },
});

const { t } = useI18n();

// Where the attribute comes from, not a lifecycle state — so these are the two colours the file
// always intended, as tones. `colorClass` used to hold them, was never bound to anything, and the two
// badges therefore rendered identically.
const attributeConfig = {
  'pre-chat': {
    icon: 'i-lucide-message-circle',
    labelKey: 'ATTRIBUTES_MGMT.BADGES.PRE_CHAT',
    tone: 'info',
  },
  resolution: {
    icon: 'i-lucide-circle-check-big',
    labelKey: 'ATTRIBUTES_MGMT.BADGES.RESOLUTION',
    tone: 'success',
  },
};
const config = computed(
  () => attributeConfig[props.type] || attributeConfig.resolution
);
</script>

<template>
  <Label :label="t(config.labelKey)" :tone="config.tone" compact>
    <template #icon>
      <Icon :icon="config.icon" class="size-3.5" />
    </template>
  </Label>
</template>
