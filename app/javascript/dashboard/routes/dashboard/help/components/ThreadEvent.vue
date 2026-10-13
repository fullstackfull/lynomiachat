<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  PLATFORM_SUPPORT_EVENT_ICONS,
  PLATFORM_SUPPORT_EVENT_FALLBACK_ICON,
} from '../constants';

// One customer-visible event in the thread.
//
// The server sends only the seven types on CUSTOMER_VISIBLE_EVENT_TYPES, with no `actor_name` for an
// operator-side event and no `metadata` at all, so there is nothing on this object to hide. A type this build
// does not have a sentence for renders with the fallback icon and its own name rather than as a blank row.
const props = defineProps({
  event: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const icon = computed(
  () =>
    PLATFORM_SUPPORT_EVENT_ICONS[props.event.event_type] ||
    PLATFORM_SUPPORT_EVENT_FALLBACK_ICON
);

const label = computed(() => {
  const key = `PLATFORM_SUPPORT.EVENTS.${props.event.event_type.toUpperCase()}`;
  const translated = t(key);

  return translated === key ? props.event.event_type : translated;
});
</script>

<template>
  <li class="flex items-center gap-2 list-none text-n-slate-10">
    <Icon :icon="icon" class="shrink-0 size-3.5" />
    <span class="text-label-small">{{ label }}</span>
    <time class="tabular-nums text-label-small">
      {{ messageTimestamp(event.created_at, 'MMM d, yyyy h:mm a') }}
    </time>
  </li>
</template>
