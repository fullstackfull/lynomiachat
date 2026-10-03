<script setup>
defineProps({
  isLoading: {
    type: Boolean,
    default: false,
  },
  noRecordsFound: {
    type: Boolean,
    default: false,
  },
  loadingMessage: {
    type: String,
    default: '',
  },
  noRecordsMessage: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div class="flex flex-col w-full h-full gap-4 font-inter">
    <slot name="header" />
    <!-- Added to render any templates that should be rendered before body -->
    <main>
      <slot name="preBody" />
      <slot v-if="isLoading" name="loading">
        <woot-loading-state :message="loadingMessage" />
      </slot>
      <!-- `emptyState` is a slot, not a prop, so a page can offer the action that fills the list
           instead of only stating that it is empty. The message stays the default. -->
      <slot v-else-if="noRecordsFound" name="emptyState">
        <p
          class="flex items-center justify-center flex-1 py-20 text-center text-body-para text-n-slate-11"
        >
          {{ noRecordsMessage }}
        </p>
      </slot>
      <slot v-else name="body" />
      <!-- Do not delete the slot below. It is required to render anything that is not defined in the above slots. -->
      <slot />
    </main>
  </div>
</template>
