<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  headerTitle: {
    type: String,
    default: '',
  },
  // What this channel's campaigns actually do. Every settings page in the product answers that question in
  // its header; the campaign pages were the only ones that left it to the reader.
  headerDescription: {
    type: String,
    default: '',
  },
  // Null while the first fetch is in flight, so the count appears once it means something rather than
  // flashing "0 campaigns" at someone who has twelve.
  count: {
    type: Number,
    default: null,
  },
  buttonLabel: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['click']);

const { t } = useI18n();
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="px-6 border-b border-n-weak">
      <div
        class="flex flex-col w-full max-w-5xl gap-4 mx-auto py-5 sm:flex-row sm:items-start sm:justify-between"
      >
        <div class="flex flex-col min-w-0 gap-1">
          <div class="flex items-center min-w-0 gap-2">
            <!-- The page had no `h1` at all: its title was a `span` styled to look like one, so the
            document outline started at the card titles. -->
            <h1 class="min-w-0 mb-0 truncate text-heading-1 text-n-slate-12">
              {{ headerTitle }}
            </h1>
            <span
              v-if="count !== null"
              class="px-2 py-0.5 rounded-full shrink-0 bg-n-alpha-2 text-label-small text-n-slate-11"
            >
              {{ t('CAMPAIGN.CARD.COUNT', { n: count }, count) }}
            </span>
          </div>
          <p
            v-if="headerDescription"
            class="max-w-2xl mb-0 text-body-main text-n-slate-11"
          >
            {{ headerDescription }}
          </p>
        </div>
        <Button
          :label="buttonLabel"
          icon="i-lucide-plus"
          size="sm"
          class="self-start shrink-0"
          @click="emit('click')"
        />
      </div>
    </header>
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-5xl py-6 mx-auto">
        <slot name="default" />
      </div>
    </main>
  </section>
</template>
