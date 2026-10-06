<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  message: {
    type: Object,
    required: true,
  },
});
</script>

<template>
  <div class="flex flex-col gap-2.5 text-n-slate-12 max-w-80">
    <div class="flex flex-col gap-1 p-3 rounded-xl bg-n-alpha-2">
      <!-- A template with buttons can still have a text header and a footer, and a builder that lets someone write
           them has to show them: without these two the preview silently dropped both. -->
      <span v-if="message.title" class="text-sm font-semibold">
        {{ message.title }}
      </span>
      <span
        v-dompurify-html="message.content"
        class="text-sm font-medium prose prose-bubble"
      />
      <span v-if="message.footer" class="text-xs text-n-slate-11">
        {{ message.footer }}
      </span>
    </div>
    <div
      v-if="message.buttons && message.buttons.length > 0"
      class="flex flex-col gap-2"
    >
      <Button
        v-for="(button, index) in message.buttons"
        :key="index"
        :label="button.text || button.title || 'Button'"
        slate
        class="!text-n-blue-11 w-full"
      />
    </div>
  </div>
</template>
