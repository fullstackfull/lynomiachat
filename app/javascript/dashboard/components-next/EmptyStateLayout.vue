<script setup>
import Policy from 'dashboard/components/policy.vue';

defineProps({
  title: {
    type: String,
    required: true,
  },
  subtitle: {
    type: String,
    default: '',
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
  // For an empty state inside a narrow column rather than a full page: no bottom reserve, no top offset, and a
  // heading at the panel's own scale instead of the page display size.
  compact: {
    type: Boolean,
    default: false,
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
      <!-- Decoration, not content: these are hardcoded sample records that show what the surface looks
      like when it has some. `pointer-events-none` stopped the mouse but left them in the tab order and in
      the accessibility tree, so a keyboard user tabbed through three campaigns that do not exist and a
      screen reader read them out as real. `inert` removes both. The mask fades the cards to nothing
      before the message starts, instead of relying on the overlay gradient to cover them -- which it did
      not: the third card still showed through the headline. -->
      <div
        v-if="showBackdrop"
        inert
        aria-hidden="true"
        class="w-full h-full space-y-4 overflow-y-hidden opacity-50 pointer-events-none [mask-image:linear-gradient(to_bottom,black_0%,black_18%,transparent_48%)]"
      >
        <slot name="empty-state-item" />
      </div>
      <div
        class="flex flex-col items-center w-full h-full"
        :class="[
          compact ? 'justify-center' : 'justify-end pb-20',
          {
            'absolute inset-x-0 bottom-0 bg-gradient-to-t from-n-surface-1 from-25% to-transparent':
              showBackdrop,
          },
        ]"
      >
        <div
          class="flex flex-col items-center justify-center gap-6"
          :class="{
            'mt-48': !showBackdrop && !compact,
          }"
        >
          <div class="flex flex-col items-center justify-center gap-3">
            <slot name="icon">
              <span
                v-if="icon"
                class="grid place-items-center rounded-overlay size-14 bg-lyn-indigo/10 text-lyn-indigo ring-1 ring-inset ring-lyn-indigo/20"
              >
                <span :class="icon" class="size-7" />
              </span>
            </slot>
            <h2
              class="text-center text-n-slate-12"
              :class="compact ? 'text-heading-3' : 'text-display'"
            >
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
