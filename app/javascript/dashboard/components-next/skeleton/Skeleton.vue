<script setup>
// The placeholder every loading surface already hand-rolls as `bg-n-slate-3 animate-pulse`, with the
// shape made explicit. Roughly twenty such blocks existed across the dashboard with four different
// base colours; this is that convention, named once.
defineProps({
  // Tailwind width/height utilities. Passed rather than hardcoded because a skeleton is only useful
  // when it matches the shape of the content it stands in for.
  width: {
    type: String,
    default: 'w-full',
  },
  height: {
    type: String,
    default: 'h-4',
  },
  shape: {
    type: String,
    default: 'line',
    validator: value => ['line', 'block', 'circle'].includes(value),
  },
});
</script>

<template>
  <div
    class="bg-n-slate-3 dark:bg-n-solid-3 animate-pulse shrink-0"
    :class="[
      width,
      height,
      {
        'rounded-sm': shape === 'line',
        'rounded-control': shape === 'block',
        'rounded-full': shape === 'circle',
      },
    ]"
    aria-hidden="true"
  />
</template>
