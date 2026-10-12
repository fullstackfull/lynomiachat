<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  // The `meta` block of an Analytics::Result payload.
  meta: {
    type: Object,
    default: () => ({}),
  },
});

const { t, te } = useI18n();

// Which source answered, and why it was chosen. The server names the reason so an operator can tell a rollup
// that was skipped because the feature is off from one skipped because its coverage disagreed with raw events.
const sourceLine = computed(() => {
  if (!props.meta.source) return '';

  const sourceLabel = t(
    `ANALYTICS.META.SOURCE.${props.meta.source.toUpperCase()}`
  );
  if (!props.meta.source_reason) return sourceLabel;

  return `${sourceLabel} — ${t(
    `ANALYTICS.META.REASON.${props.meta.source_reason.toUpperCase()}`
  )}`;
});

const footnote = computed(() =>
  t('ANALYTICS.META.FOOTNOTE', {
    since: props.meta.since,
    until: props.meta.until,
    timezone: props.meta.timezone,
    grouping: props.meta.group_by
      ? t(`ANALYTICS.GROUP_BY.${props.meta.group_by.toUpperCase()}`)
      : '',
  })
);

// A warning names its scope and its reason as snake_case tokens, which are identifiers and not copy. Each is
// looked up, and falls back to the token itself so a reason this build has no wording for is still readable
// rather than a blank line.
const localized = (group, token) => {
  const key = `ANALYTICS.META.${group}.${token.toUpperCase()}`;
  return te(key) ? t(key) : token;
};

const warnings = computed(() =>
  (props.meta.warnings || []).map(warning => ({
    key: `${warning.scope}-${warning.reason}`,
    text: t('ANALYTICS.META.WARNING', {
      scope: localized('WARNING_SCOPE', warning.scope),
      reason: localized('WARNING_REASON', warning.reason),
    }),
  }))
);
</script>

<template>
  <div class="flex flex-col gap-2">
    <ul
      v-if="warnings.length"
      class="flex flex-col gap-1 p-3 m-0 list-none border rounded-xl bg-n-amber-3 border-n-amber-4"
    >
      <li
        v-for="warning in warnings"
        :key="warning.key"
        class="text-body-main text-n-amber-11"
      >
        {{ warning.text }}
      </li>
    </ul>
    <p class="m-0 text-label-small text-n-slate-10">{{ footnote }}</p>
    <p v-if="sourceLine" class="m-0 text-label-small text-n-slate-10">
      {{ sourceLine }}
    </p>
  </div>
</template>
