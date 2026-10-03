<script setup>
import { computed } from 'vue';

const props = defineProps({
  label: {
    type: [Object, String],
    required: true,
  },
  compact: {
    type: Boolean,
    default: false,
  },
  color: {
    type: String,
    default: 'slate',
    validator: value =>
      ['slate', 'amber', 'teal', 'ruby', 'blue', 'iris'].includes(value),
  },
  // The semantic a status carries, rather than the colour it happens to be painted. About twenty
  // independent status maps across the product had already settled on the same associations; naming
  // them means a new status picks a meaning and inherits the colour, instead of picking a colour.
  tone: {
    type: String,
    default: '',
    validator: value =>
      ['', 'neutral', 'success', 'warning', 'danger', 'info', 'read'].includes(
        value
      ),
  },
  // `label` is the user-applied chip this component was built for: a tinted surface inside a hairline
  // outline. `solid` is the status badge the product writes by hand in sixty places. `subtle` is the
  // deliberate neutral-background-with-tinted-text chip that account health, campaign cards, article
  // cards and the search results all use — a variant, not an accident.
  variant: {
    type: String,
    default: 'label',
    validator: value => ['label', 'solid', 'subtle'].includes(value),
  },
});

const TONE_COLORS = {
  neutral: 'slate',
  success: 'teal',
  warning: 'amber',
  danger: 'ruby',
  info: 'blue',
  read: 'iris',
};

const VARIANT_CLASSES = {
  label: {
    slate: 'bg-n-label-color outline-n-label-border text-n-slate-12',
    amber: 'bg-n-amber-2 outline-n-amber-4 text-n-amber-11',
    teal: 'bg-n-teal-2 outline-n-teal-4 text-n-teal-11',
    ruby: 'bg-n-ruby-2 outline-n-ruby-4 text-n-ruby-11',
    blue: 'bg-n-blue-2 outline-n-blue-4 text-n-blue-11',
    iris: 'bg-n-iris-2 outline-n-iris-4 text-n-iris-11',
  },
  solid: {
    slate: 'bg-n-slate-3 text-n-slate-11',
    amber: 'bg-n-amber-3 text-n-amber-11',
    teal: 'bg-n-teal-3 text-n-teal-11',
    ruby: 'bg-n-ruby-3 text-n-ruby-11',
    blue: 'bg-n-blue-3 text-n-blue-11',
    iris: 'bg-n-iris-3 text-n-iris-11',
  },
  subtle: {
    slate: 'bg-n-alpha-2 text-n-slate-11',
    amber: 'bg-n-alpha-2 text-n-amber-11',
    teal: 'bg-n-alpha-2 text-n-teal-11',
    ruby: 'bg-n-alpha-2 text-n-ruby-11',
    blue: 'bg-n-alpha-2 text-n-blue-11',
    iris: 'bg-n-alpha-2 text-n-iris-11',
  },
};

const isStringLabel = computed(() => typeof props.label === 'string');

const labelTitle = computed(() => {
  return isStringLabel.value ? props.label : props.label?.title;
});

const labelDescription = computed(() => {
  return (!isStringLabel.value && props.label?.description) || '';
});

const labelColor = computed(() => {
  return isStringLabel.value ? null : props.label.color;
});

const resolvedColor = computed(() => TONE_COLORS[props.tone] || props.color);

const colorClasses = computed(
  () => VARIANT_CLASSES[props.variant][resolvedColor.value]
);
</script>

<template>
  <div
    :title="labelDescription"
    class="inline-flex items-center flex-shrink-0"
    :class="[
      colorClasses,
      variant === 'label'
        ? 'rounded-lg -outline-offset-1 outline outline-1'
        : '',
      compact ? 'px-1.5 h-6 gap-1 rounded-md' : 'px-2.5 h-8 gap-1.5 rounded-lg',
    ]"
  >
    <span
      v-if="labelColor"
      class="rounded-sm flex-shrink-0"
      :class="compact ? 'size-1.5' : 'size-2'"
      :style="{ background: labelColor }"
    />
    <slot v-else name="icon" />
    <span
      class="whitespace-nowrap"
      :class="compact ? 'text-label-small' : 'text-label !font-420'"
    >
      {{ labelTitle }}
    </span>
    <slot name="action" />
  </div>
</template>
