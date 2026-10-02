<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { NODE_GROUPS, NODE_ICONS } from '../flowGraph';

// The node types by group. A type is added by dragging it onto the canvas, or by clicking it (placed in view).
const props = defineProps({
  commerceEnabled: { type: Boolean, default: false },
});
const emit = defineEmits(['add']);

const { t } = useI18n();

const groups = NODE_GROUPS.filter(
  group => group.key !== 'COMMERCE' || props.commerceEnabled
);

const onDragStart = (event, type) => {
  event.dataTransfer.setData('application/lynomia-flow-node', type);
  event.dataTransfer.effectAllowed = 'move';
};
</script>

<template>
  <aside
    class="hidden md:flex flex-col gap-4 p-3 overflow-y-auto border-e border-n-weak w-56 shrink-0"
  >
    <section v-for="group in groups" :key="group.key">
      <h3 class="mb-2 text-xs font-medium uppercase text-n-slate-10">
        {{ t(`FLOW_BUILDER.GROUPS.${group.key}`) }}
      </h3>
      <ul class="flex flex-col gap-1 list-none m-0">
        <li v-for="type in group.types" :key="type">
          <button
            type="button"
            draggable="true"
            class="flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-lg text-start text-n-slate-12 hover:bg-n-alpha-2 cursor-grab"
            :data-test-id="`flow-palette-${type}`"
            @dragstart="onDragStart($event, type)"
            @click="emit('add', type)"
          >
            <Icon :icon="NODE_ICONS[type]" class="size-4 text-n-slate-11" />
            <span class="truncate">
              {{ t(`FLOW_BUILDER.NODES.${type.toUpperCase()}`) }}
            </span>
          </button>
        </li>
      </ul>
    </section>
  </aside>
</template>
