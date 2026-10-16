<script setup>
import { computed, ref } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { MESSAGE_STATUS } from './constants';

import Icon from 'next/icon/Icon.vue';

const { status } = defineProps({
  status: {
    type: String,
    required: true,
    validator: value => Object.values(MESSAGE_STATUS).includes(value),
  },
});

const { t } = useI18n();

const progresIconSequence = [
  'i-lucide-clock-1',
  'i-lucide-clock-2',
  'i-lucide-clock-3',
  'i-lucide-clock-4',
  'i-lucide-clock-5',
  'i-lucide-clock-6',
  'i-lucide-clock-7',
  'i-lucide-clock-8',
  'i-lucide-clock-9',
  'i-lucide-clock-10',
  'i-lucide-clock-11',
  'i-lucide-clock-12',
];

const progessIcon = ref(progresIconSequence[0]);

const rotateIcon = () => {
  const currentIndex = progresIconSequence.indexOf(progessIcon.value);
  const nextIndex = (currentIndex + 1) % progresIconSequence.length;
  progessIcon.value = progresIconSequence[nextIndex];
};

useIntervalFn(rotateIcon, 500, {
  immediate: status === MESSAGE_STATUS.PROGRESS,
  immediateCallback: false,
});

const statusIcon = computed(() => {
  const statusIconMap = {
    [MESSAGE_STATUS.SENT]: 'i-lucide-check',
    [MESSAGE_STATUS.DELIVERED]: 'i-lucide-check-check',
    [MESSAGE_STATUS.READ]: 'i-lucide-check-check',
    // Deliberately not a check of any kind, and deliberately not the clock: a check claims the provider
    // confirmed something and a clock claims we are still trying. Neither is true when nothing reported.
    [MESSAGE_STATUS.UNKNOWN]: 'i-lucide-circle-help',
  };

  return statusIconMap[status];
});

const statusColor = computed(() => {
  const statusIconMap = {
    [MESSAGE_STATUS.SENT]: 'text-n-slate-11',
    [MESSAGE_STATUS.DELIVERED]: 'text-n-slate-11',
    // Was a hardcoded `#7EB6FF`, which is a single value for two themes: on the light outgoing bubble it
    // sat at roughly 2:1 against its own background, so the one state an agent looks for was the hardest
    // of the four to see. `n-iris-11` is the theme-aware accent and is also further from the grey of
    // DELIVERED than a pale blue is, which matters because the two share a glyph.
    [MESSAGE_STATUS.READ]: 'text-n-iris-11',
    [MESSAGE_STATUS.UNKNOWN]: 'text-n-slate-11',
  };

  return statusIconMap[status];
});

const tooltipText = computed(() => {
  const statusTextMap = {
    [MESSAGE_STATUS.SENT]: t('CHAT_LIST.SENT'),
    [MESSAGE_STATUS.DELIVERED]: t('CHAT_LIST.DELIVERED'),
    [MESSAGE_STATUS.READ]: t('CHAT_LIST.MESSAGE_READ'),
    [MESSAGE_STATUS.PROGRESS]: t('CHAT_LIST.SENDING'),
    [MESSAGE_STATUS.UNKNOWN]: t('CHAT_LIST.DELIVERY_UNKNOWN'),
  };

  return statusTextMap[status];
});
</script>

<template>
  <span class="inline-flex items-center">
    <Icon
      v-if="status === MESSAGE_STATUS.PROGRESS"
      v-tooltip.top-start="tooltipText"
      :icon="progessIcon"
      class="text-n-slate-11 size-[14px]"
      aria-hidden="true"
      role="presentation"
    />
    <Icon
      v-else
      v-tooltip.top-start="tooltipText"
      :icon="statusIcon"
      :class="statusColor"
      class="size-[14px]"
      aria-hidden="true"
      role="presentation"
    />
    <!-- The tooltip is the only place this state was named, and a tooltip is not an accessible name: to a
    screen reader the whole indicator was an empty span. Delivery state is also the one thing here carried
    by colour between DELIVERED and READ, which share a glyph. -->
    <span class="sr-only">{{ tooltipText }}</span>
  </span>
</template>
