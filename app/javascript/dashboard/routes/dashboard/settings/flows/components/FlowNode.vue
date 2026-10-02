<script setup>
import { computed, inject } from 'vue';
import { useI18n } from 'vue-i18n';
import { Handle, Position } from '@vue-flow/core';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { NODE_ICONS, isOptionalOutput, nodeOutputs } from '../flowGraph';

// One node on the canvas: its type, a preview of what it does, and one connector per output (a choice node has one
// per option). Errors from the server's validation and the node a test or session is at are marked.
const props = defineProps({
  id: { type: String, required: true },
  data: { type: Object, required: true },
  selected: { type: Boolean, default: false },
});

const { t } = useI18n();
const builder = inject('flowBuilder');

const type = computed(() => props.data.type);
const config = computed(() => props.data.data || {});
const outputs = computed(() =>
  nodeOutputs(builder.nodeTypes.value, type.value, config.value)
);
const hasErrors = computed(() => builder.errorNodeIds.value.has(props.id));
const isActive = computed(() => builder.activeNodeId.value === props.id);

const summary = computed(() => {
  const value = config.value;
  if (value.text) return value.text;
  if (value.labels?.length) return value.labels.join(', ');
  if (value.url) return value.url;
  if (value.key) return value.key;
  if (value.seconds)
    return t('FLOW_BUILDER.NODE.SECONDS', { n: value.seconds });
  if (value.reason) return value.reason;
  if (value.conditions?.length)
    return t('FLOW_BUILDER.NODE.CONDITIONS', { n: value.conditions.length });
  return '';
});

const outputLabel = output => {
  const option = (config.value.options || []).find(item => item.id === output);
  if (option) return option.title || t('FLOW_BUILDER.NODE.UNTITLED_OPTION');
  return t(`FLOW_BUILDER.OUTPUTS.${output.toUpperCase()}`);
};
</script>

<template>
  <div
    class="w-60 rounded-xl bg-n-solid-1 shadow-sm outline outline-1 -outline-offset-1"
    :class="{
      'outline-n-ruby-9': hasErrors,
      'outline-n-teal-9 outline-2': isActive && !hasErrors,
      'outline-n-blue-9 outline-2': selected && !hasErrors && !isActive,
      'outline-n-weak': !selected && !hasErrors && !isActive,
    }"
    :data-test-id="`flow-node-${id}`"
  >
    <Handle
      v-if="type !== 'start'"
      type="target"
      :position="Position.Top"
      class="!size-3 !rounded-full !bg-n-slate-9 !border-2 !border-n-solid-1"
    />
    <div class="flex items-center gap-2 px-3 py-2 border-b border-n-weak">
      <Icon :icon="NODE_ICONS[type]" class="size-4 shrink-0 text-n-slate-11" />
      <span class="text-label-small text-n-slate-12 truncate">
        {{ t(`FLOW_BUILDER.NODES.${type.toUpperCase()}`) }}
      </span>
      <Icon
        v-if="hasErrors"
        icon="i-lucide-circle-alert"
        class="size-4 shrink-0 ms-auto text-n-ruby-9"
      />
    </div>
    <p
      v-if="summary"
      dir="auto"
      class="px-3 pt-2 mb-0 text-xs text-n-slate-11 line-clamp-2 break-words"
    >
      {{ summary }}
    </p>
    <div v-if="outputs.length" class="flex flex-col gap-1 py-2">
      <div
        v-for="output in outputs"
        :key="output"
        class="relative flex items-center justify-end h-6 ps-3 pe-4"
      >
        <span
          dir="auto"
          class="text-xs truncate"
          :class="
            isOptionalOutput(builder.nodeTypes.value, type, output)
              ? 'text-n-slate-10'
              : 'text-n-slate-12'
          "
        >
          {{ outputLabel(output) }}
        </span>
        <Handle
          :id="output"
          type="source"
          :position="Position.Right"
          class="!size-3 !rounded-full !bg-n-blue-9 !border-2 !border-n-solid-1"
          :data-test-id="`flow-handle-${id}-${output}`"
        />
      </div>
    </div>
  </div>
</template>
