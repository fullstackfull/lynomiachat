<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['add']);

const addLabel = () => {
  emit('add');
};
</script>

<template>
  <Button
    faded
    xs
    icon="i-lucide-plus"
    class="mb-0.5 me-0.5 !rounded-sm"
    :label="$t('CONTACT_PANEL.LABELS.CONVERSATION.ADD_BUTTON')"
    @click="addLabel"
  />
</template>
