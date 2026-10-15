<script setup>
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import FeaturePlaceholder from './FeaturePlaceholder.vue';

defineProps({
  message: {
    type: String,
    required: true,
  },
  icon: {
    type: String,
    default: 'i-lucide-messages-square',
  },
});
</script>

<template>
  <EmptyStateLayout
    compact
    :show-backdrop="false"
    :icon="icon"
    :title="message"
    class="h-full"
  >
    <template #actions>
      <FeaturePlaceholder />
    </template>
  </EmptyStateLayout>
</template>
