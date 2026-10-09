<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
import {
  CONTACT_ACTIVITY_ICONS,
  CONTACT_ACTIVITY_FALLBACK_ICON,
} from 'dashboard/constants/contactActivity';

const props = defineProps({
  // One Contacts::ActivityTimeline::Entry as the API returns it.
  entry: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

// The chips a reader needs to act on the row, taken from the entry's own typed meta. Nothing is derived or
// guessed: a value the server did not send simply has no chip.
const CHIP_KEYS = [
  'rule_name',
  'campaign_title',
  'flow_name',
  'template_name',
  'action_type',
  'provider',
  'error_code',
  'failure_code',
  'skip_reason',
  'end_reason',
  'match_source',
  'currency',
];

const occurredAt = computed(() => new Date(props.entry.occurred_at));

const icon = computed(
  () =>
    CONTACT_ACTIVITY_ICONS[props.entry.kind] || CONTACT_ACTIVITY_FALLBACK_ICON
);

// A kind the server adds later still renders: its own key is shown rather than an empty label.
const title = computed(() =>
  t(
    `CONTACTS_LAYOUT.SIDEBAR.ACTIVITY.KIND.${props.entry.kind.toUpperCase()}`,
    props.entry.kind
  )
);

const chips = computed(() =>
  CHIP_KEYS.map(key => props.entry.meta?.[key]).filter(Boolean)
);

const rating = computed(() => props.entry.meta?.rating);

const duration = computed(() => props.entry.meta?.duration_seconds);
</script>

<template>
  <li class="flex gap-3 py-3">
    <span
      class="mt-0.5 shrink-0 size-4 text-n-slate-10"
      :class="icon"
      aria-hidden="true"
    />
    <div class="flex flex-col gap-1 min-w-0">
      <div class="flex items-baseline justify-between gap-2">
        <span class="text-heading-3 text-n-slate-12">{{ title }}</span>
        <time
          :datetime="entry.occurred_at"
          :title="dynamicTime(occurredAt.getTime() / 1000)"
          class="shrink-0 tabular-nums text-label-small text-n-slate-10"
        >
          {{ shortTimestamp(dynamicTime(occurredAt.getTime() / 1000), true) }}
        </time>
      </div>
      <p
        v-if="entry.summary"
        class="m-0 break-words text-body-main text-n-slate-11"
      >
        {{ entry.summary }}
      </p>
      <div
        v-if="chips.length || rating || duration"
        class="flex flex-wrap gap-1.5"
      >
        <span
          v-if="rating"
          class="px-1.5 py-0.5 rounded-md bg-n-amber-3 text-label-small text-n-amber-11"
        >
          {{ t('CONTACTS_LAYOUT.SIDEBAR.ACTIVITY.RATING', { value: rating }) }}
        </span>
        <span
          v-if="duration"
          class="px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-label-small text-n-slate-11"
        >
          {{
            t('CONTACTS_LAYOUT.SIDEBAR.ACTIVITY.DURATION', { value: duration })
          }}
        </span>
        <span
          v-for="chip in chips"
          :key="chip"
          class="px-1.5 py-0.5 rounded-md bg-n-alpha-2 text-label-small text-n-slate-11"
        >
          {{ chip }}
        </span>
      </div>
    </div>
  </li>
</template>
