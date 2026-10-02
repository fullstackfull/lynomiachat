<script setup>
import { computed } from 'vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { newOption } from '../flowGraph';

// The options of a Buttons or List node, within the channel's limits (from the server). Each option keeps its id: the
// flow routes by that id, never by the title, so renaming an option keeps its connection.
const props = defineProps({
  limits: { type: Object, required: true },
  withDescription: { type: Boolean, default: false },
});
const options = defineModel({ type: Array, default: () => [] });

const canAdd = computed(() => options.value.length < props.limits.max);

const update = (index, field, value) => {
  options.value = options.value.map((option, i) =>
    i === index ? { ...option, [field]: value } : option
  );
};
const add = () => {
  options.value = [...options.value, newOption()];
};
const remove = index => {
  options.value = options.value.filter((_, i) => i !== index);
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      v-for="(option, index) in options"
      :key="option.id"
      class="flex flex-col gap-1 p-2 rounded-lg bg-n-alpha-1"
    >
      <div class="flex items-center gap-2">
        <Input
          :model-value="option.title"
          class="flex-1"
          :placeholder="$t('FLOW_BUILDER.CONFIG.OPTION_TITLE')"
          :message="
            option.title.length > limits.title
              ? $t('FLOW_BUILDER.CONFIG.TOO_LONG', { n: limits.title })
              : ''
          "
          :message-type="option.title.length > limits.title ? 'error' : 'info'"
          @update:model-value="update(index, 'title', $event)"
        />
        <NextButton
          icon="i-lucide-trash-2"
          slate
          ghost
          sm
          :disabled="options.length === 1"
          @click="remove(index)"
        />
      </div>
      <Input
        v-if="withDescription"
        :model-value="option.description || ''"
        :placeholder="$t('FLOW_BUILDER.CONFIG.OPTION_DESCRIPTION')"
        @update:model-value="update(index, 'description', $event)"
      />
    </div>
    <div>
      <NextButton
        icon="i-lucide-plus"
        blue
        faded
        sm
        :disabled="!canAdd"
        :label="$t('FLOW_BUILDER.CONFIG.ADD_OPTION', { n: limits.max })"
        @click="add"
      />
    </div>
  </div>
</template>
