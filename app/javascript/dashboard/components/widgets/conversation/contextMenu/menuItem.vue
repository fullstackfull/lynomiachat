<script setup>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  option: {
    type: Object,
    default: () => {},
  },
  variant: {
    type: String,
    default: 'default',
  },
});

// The row's own click handler belongs to whoever placed it, so Enter and Space dispatch a real click rather
// than a second event the parent would have to listen for. Without this the menu is mouse-only.
const activate = event => event.currentTarget.click();
</script>

<template>
  <div
    class="group text-n-slate-12 focus-ring flex items-center flex-nowrap gap-2 p-1 min-h-7 min-w-[12.5rem] max-w-[18rem] rounded-md overflow-hidden cursor-pointer hover:bg-n-brand hover:text-white"
    role="button"
    tabindex="0"
    @keydown.enter.prevent="activate"
    @keydown.space.prevent="activate"
  >
    <fluent-icon
      v-if="variant === 'icon' && option.icon"
      :icon="option.icon"
      size="14"
      class="flex-shrink-0"
    />
    <span
      v-if="
        (variant === 'label' || variant === 'label-assigned') && option.color
      "
      class="flex-shrink-0 w-4 h-4 rounded-full border border-solid border-n-strong"
      :style="{ backgroundColor: option.color }"
    />
    <Avatar
      v-if="variant === 'agent'"
      :name="option.label"
      :src="option.thumbnail"
      :icon-name="option.iconName"
      :status="option.status === 'online' ? option.status : null"
      :size="20"
      class="flex-shrink-0"
    >
      <template v-if="option.iconName && option.thumbnail" #badge>
        <div
          class="absolute z-20 flex items-center justify-center rounded-full outline outline-1 outline-n-weak bg-n-solid-1 -bottom-0.5 ltr:-right-0.5 rtl:-left-0.5 size-3"
        >
          <Icon icon="i-lucide-bot" class="text-n-slate-11 size-2" />
        </div>
      </template>
    </Avatar>
    <!-- Truncates instead of being cut off by the row's fixed width, and carries the full text as a tooltip:
         agent, team and label names are routinely longer than 200px of row. -->
    <p
      :title="option.label"
      class="my-0 text-label-small truncate min-w-0 flex-1"
    >
      {{ option.label }}
    </p>
    <Icon
      v-if="variant === 'label-assigned'"
      icon="i-lucide-check"
      class="flex-shrink-0 size-3.5 text-n-brand group-hover:text-white"
    />
  </div>
</template>
