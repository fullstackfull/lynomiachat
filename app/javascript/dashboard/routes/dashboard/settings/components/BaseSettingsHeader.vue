<script setup>
import { computed, useSlots } from 'vue';
import { getHelpUrlForFeature } from '../../../../helper/featureHelper';
import BackButton from '../../../../components/widgets/BackButton.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  linkText: {
    type: String,
    default: '',
  },
  featureName: {
    type: String,
    default: '',
  },
  backButtonLabel: {
    type: String,
    default: '',
  },
  searchPlaceholder: {
    type: String,
    default: '',
  },
});

const slots = useSlots();

const searchQuery = defineModel('searchQuery', { type: String, default: '' });

// Reactive: several pages bind `featureName` to data that arrives after setup, and a one-shot read
// left those pages permanently without their help link.
//
// The link used to sit inside CustomBrandPolicyWrapper, which hid it on every branded installation -- correct when
// the only destination was upstream's help centre. `getHelpUrlForFeature` now decides per feature: a branded
// installation gets its own documentation article, or nothing where it has no article, and never an upstream URL
// (docs/global-documentation/12-contextual-help.md). The wrapper would only hide a link that is ours.
const helpURL = computed(() => getHelpUrlForFeature(props.featureName));
</script>

<template>
  <div class="flex flex-col items-start w-full">
    <BackButton
      v-if="backButtonLabel"
      compact
      :button-label="backButtonLabel"
      class="my-1"
    />
    <div
      v-if="title"
      class="flex items-center justify-between w-full gap-4 min-h-8 mb-2"
    >
      <slot name="title">
        <h1 class="text-heading-1 text-n-slate-12">
          {{ title }}
        </h1>
      </slot>
    </div>
    <div
      v-if="
        description ||
        $slots.description ||
        (linkText && helpURL) ||
        $slots.meta
      "
      class="flex flex-col w-full gap-1.5 text-n-slate-11"
    >
      <p
        v-if="description || $slots.description"
        class="mb-0 line-clamp-5 sm:line-clamp-none max-w-3xl text-body-main"
      >
        <slot name="description">{{ description }}</slot>
      </p>
      <a
        v-if="helpURL && linkText"
        :href="helpURL"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 text-sm font-medium w-fit text-n-blue-11 hover:underline mb-2"
      >
        {{ linkText }}
        <Icon
          icon="i-lucide-chevron-right"
          class="flex-shrink-0 text-n-blue-11 size-4"
        />
      </a>
      <slot name="meta" />
    </div>
  </div>
  <div
    v-if="searchPlaceholder || slots.actions || slots.tabs"
    class="gap-3 flex flex-wrap sm:flex-nowrap justify-between mt-3 sm:mt-4 min-w-0"
  >
    <div
      v-if="slots.tabs || searchPlaceholder"
      class="flex items-center gap-3 min-w-0 w-full sm:w-auto"
    >
      <slot name="tabs" />
      <Input
        v-if="searchPlaceholder"
        v-model="searchQuery"
        :placeholder="searchPlaceholder"
        class="group w-full sm:w-56 min-w-0 flex [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8 [&>input]:!rounded-[0.625rem]"
        size="sm"
        type="search"
      >
        <template #prefix>
          <Icon
            icon="i-lucide-search"
            class="absolute top-1/2 -translate-y-1/2 text-n-slate-11 group-focus-within:text-n-brand size-3.5 ltr:left-2.5 rtl:right-2.5"
          />
        </template>
      </Input>
    </div>
    <div
      class="flex items-center gap-3 shrink-0"
      :class="{ 'flex-row-reverse sm:flex-row': !slots.tabs }"
    >
      <slot name="count" />
      <div
        v-if="slots.count && slots.actions"
        class="w-px h-3 rounded-lg bg-n-weak ltr:ml-1 ltr:mr-2 rtl:ml-2 rtl:mr-1 flex-shrink-0"
      />
      <slot name="actions" />
    </div>
  </div>
</template>
