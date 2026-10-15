<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  label: {
    type: Object,
    default: null,
  },
  isHovered: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['remove', 'hover']);

const { t } = useI18n();

const handleRemoveLabel = () => {
  emit('remove', props.label);
};

const handleMouseEnter = () => {
  // Notify parent component when this label is hovered
  // Added this to show the remove button with transition when hovering over the label
  // This will solve the flickering issue when hovering over the last label item
  emit('hover', props.label?.id);
};
</script>

<template>
  <div
    class="flex items-center px-1 py-1 overflow-hidden transition-all duration-300 ease-out rounded-md bg-n-alpha-2 h-7"
    @mouseenter="handleMouseEnter"
  >
    <div
      class="w-2 h-2 m-1 rounded-sm"
      :style="{ backgroundColor: label.color }"
    />
    <span class="text-sm text-n-slate-12 ltr:mr-px rtl:ml-px">
      {{ label.title }}
    </span>
    <!-- `focus-within` so the button is not a hover-only control: tabbing to it used to
      leave it collapsed to zero width and fully transparent, i.e. focused and invisible.
      It also had no text, so it announced only "button" next to the label's name. -->
    <div
      class="w-0 flex relative ltr:left-1 rtl:right-1 flex-shrink-0 overflow-hidden transition-[width] duration-300 ease-out focus-within:w-6"
      :class="{ 'w-6': isHovered }"
    >
      <Button
        class="transition-opacity duration-200 !h-7 ltr:rounded-r-md rtl:rounded-l-md ltr:rounded-l-none rtl:rounded-r-none w-6 bg-transparent focus-within:opacity-100 focus:opacity-100"
        :class="{ 'opacity-0': !isHovered, 'opacity-100': isHovered }"
        type="button"
        slate
        xs
        faded
        icon="i-lucide-x"
        :aria-label="t('LABEL.REMOVE', { name: label?.title })"
        @click="handleRemoveLabel"
      />
    </div>
  </div>
</template>
