<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { CONVERSATION_STATUS } from 'shared/constants/messages';

import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  status: {
    type: String,
    default: '',
  },
  showEmpty: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

const icons = {
  [CONVERSATION_STATUS.OPEN]: 'i-woot-status-open',
  [CONVERSATION_STATUS.RESOLVED]: 'i-woot-status-resolved',
  [CONVERSATION_STATUS.PENDING]: 'i-woot-status-pending',
  [CONVERSATION_STATUS.SNOOZED]: 'i-woot-status-snoozed',
};

const statusLabels = {
  [CONVERSATION_STATUS.OPEN]: 'CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.open.TEXT',
  [CONVERSATION_STATUS.RESOLVED]:
    'CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.resolved.TEXT',
  [CONVERSATION_STATUS.PENDING]:
    'CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.pending.TEXT',
  [CONVERSATION_STATUS.SNOOZED]:
    'CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.snoozed.TEXT',
};

const iconName = computed(() => {
  if (props.status && icons[props.status]) {
    return icons[props.status];
  }
  return props.showEmpty ? 'i-woot-status-empty' : '';
});

// The tooltip used to print the raw enum, so every locale read `open` / `snoozed` in lowercase English —
// while the priority column beside it was translated.
const tooltipContent = computed(() =>
  props.status && statusLabels[props.status]
    ? t(statusLabels[props.status])
    : ''
);
</script>

<template>
  <Icon
    v-tooltip.top="{
      content: tooltipContent,
      delay: { show: 500, hide: 0 },
    }"
    role="img"
    :aria-label="tooltipContent"
    :icon="iconName"
    class="size-4 flex-shrink-0"
  />
</template>
