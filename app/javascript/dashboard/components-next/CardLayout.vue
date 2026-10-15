<script setup>
defineProps({
  layout: {
    type: String,
    default: 'col',
  },
  selectable: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['click']);

const handleClick = () => {
  emit('click');
};
</script>

<template>
  <div
    class="flex flex-col w-full outline-1 outline outline-n-container -outline-offset-1 group/cardLayout rounded-xl bg-n-solid-2"
  >
    <!-- A row card holds one record on one or two lines, so it is set tight; a column card holds a block of
         content and keeps the roomier padding. The old single value gave a two-line contact 40px of vertical
         padding around 44px of content, which is why seven contacts filled a 900px screen. -->
    <div
      class="flex w-full gap-3"
      :class="[
        layout === 'col'
          ? 'flex-col py-5'
          : 'flex-row justify-between items-center py-3',
        selectable ? 'px-8 py-5' : 'px-5',
      ]"
      @click="handleClick"
    >
      <slot />
    </div>

    <slot name="after" />
  </div>
</template>
