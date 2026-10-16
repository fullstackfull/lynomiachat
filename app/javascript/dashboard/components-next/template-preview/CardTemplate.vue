<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
});

// The two buttons were "Call us to order" and "Visit our store": hardcoded English, invented, and
// bound to nothing, so the preview showed those two labels whatever the Twilio card actually
// carried. `QuickReplyTemplate` already reads the same shape for the same kind of card, so this
// reads it the same way rather than inventing a second convention.
const actions = computed(() => props.message.actions || []);
</script>

<template>
  <div
    class="rounded-xl divide-y bg-n-alpha-2 divide-n-strong text-n-slate-12 max-w-80"
  >
    <div class="px-3 py-2.5">
      <img :src="message.image_url" class="w-full max-h-44 rounded-lg" />
      <div class="flex flex-col gap-2 pt-2.5">
        <h6 class="font-semibold">{{ message.title }}</h6>
        <span
          v-dompurify-html="message.content"
          class="text-sm prose prose-bubble"
        />
      </div>
    </div>
    <div
      v-for="(action, index) in actions"
      :key="index"
      class="flex justify-center items-center p-3"
    >
      <Button
        :label="action.title || action.text || 'Button'"
        link
        class="hover:!no-underline"
      />
    </div>
  </div>
</template>
