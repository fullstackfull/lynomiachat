<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  fromUnixTime,
  format,
  isToday,
  isYesterday,
  isThisYear,
} from 'date-fns';

const props = defineProps({
  timestamp: { type: Number, required: true },
});

const { t } = useI18n();

// Named days for the two a reader holds in their head, a weekday for the rest of this year, and a full
// date once the year is ambiguous. The weekday is worth its characters: "Monday, Oct 13" answers "how
// long did this customer wait" without arithmetic, which a bare date does not.
const label = computed(() => {
  const date = fromUnixTime(props.timestamp);
  if (isToday(date)) return t('CONVERSATION.DATE_SEPARATOR.TODAY');
  if (isYesterday(date)) return t('CONVERSATION.DATE_SEPARATOR.YESTERDAY');
  if (isThisYear(date)) return format(date, 'EEEE, MMM d');
  return format(date, 'MMM d, yyyy');
});
</script>

<template>
  <li
    role="separator"
    :aria-label="label"
    class="flex items-center gap-3 my-4 list-none"
  >
    <span class="flex-1 h-px bg-n-strong" />
    <span class="text-xs font-medium text-n-slate-11">{{ label }}</span>
    <span class="flex-1 h-px bg-n-strong" />
  </li>
</template>
