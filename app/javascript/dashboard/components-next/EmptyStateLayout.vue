<script setup>
import Policy from 'dashboard/components/policy.vue';

defineProps({
  title: {
    type: String,
    required: true,
  },
  subtitle: {
    type: String,
    required: true,
  },
  // An icon above the title, for the surfaces that built their own card-shaped empty state to get one.
  icon: {
    type: String,
    default: '',
  },
  actionPerms: {
    type: Array,
    default: () => [],
  },
  showBackdrop: {
    type: Boolean,
    default: true,
  },
});
</script>

<template>
  <section
    class="relative flex flex-col items-center justify-center w-full h-full overflow-hidden"
  >
    <div
      class="relative w-full max-w-5xl mx-auto overflow-hidden h-full max-h-[28rem]"
    >
      <div
        v-if="showBackdrop"
        class="w-full h-full space-y-4 overflow-y-hidden opacity-50 pointer-events-none"
      >
        <slot name="empty-state-item" />
      </div>
      <div
        class="flex flex-col items-center justify-end w-full h-full pb-20"
        :class="{
          'absolute inset-x-0 bottom-0 bg-gradient-to-t from-n-surface-1 from-25% to-transparent':
            showBackdrop,
        }"
      >
        <div
          class="flex flex-col items-center justify-center gap-6"
          :class="{
            'mt-48': !showBackdrop,
          }"
        >
          <div class="flex flex-col items-center justify-center gap-3">
            <slot name="icon">
              <span
                v-if="icon"
                class="grid place-items-center rounded-overlay size-12 bg-n-alpha-2 text-n-slate-11"
              >
                <span :class="icon" class="size-6" />
              </span>
            </slot>
            <h2 class="text-center text-display text-n-slate-12">
              {{ title }}
            </h2>
            <p
              v-if="subtitle"
              class="max-w-xl text-center text-body-para text-n-slate-11"
            >
              {{ subtitle }}
            </p>
          </div>
          <Policy :permissions="actionPerms">
            <slot name="actions" />
          </Policy>
        </div>
      </div>
    </div>
  </section>
</template>
