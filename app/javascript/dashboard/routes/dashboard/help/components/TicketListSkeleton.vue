<script setup>
import Skeleton from 'dashboard/components-next/skeleton/Skeleton.vue';

// The list's first load. Card-shaped rather than a spinner so the page does not jump when the real cards
// arrive, using the design system's named skeleton instead of another hand-rolled animate-pulse block.
defineProps({
  rows: {
    type: Number,
    default: 3,
  },
});
</script>

<template>
  <ul
    data-test-id="platform-support-list-skeleton"
    class="flex flex-col gap-3 p-0 m-0 list-none"
    :aria-busy="true"
  >
    <li
      v-for="row in rows"
      :key="row"
      class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="flex items-center justify-between gap-2">
        <Skeleton width="w-24" height="h-3" />
        <Skeleton width="w-16" height="h-3" />
      </div>
      <Skeleton width="w-2/3" height="h-4" />
      <div class="flex items-center gap-2">
        <Skeleton width="w-16" height="h-5" shape="block" />
        <Skeleton width="w-20" height="h-5" shape="block" />
      </div>
    </li>
  </ul>
</template>
