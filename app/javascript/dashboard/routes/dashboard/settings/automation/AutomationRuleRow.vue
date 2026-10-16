<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDelay } from 'dashboard/helper/automationHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import WootLabel from 'dashboard/components-next/label/Label.vue';
import { BaseTableRow, BaseTableCell } from 'dashboard/components-next/table';

const props = defineProps({
  automation: {
    type: Object,
    required: true,
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle', 'edit', 'delete', 'clone']);

const { t, locale } = useI18n();

// `created_on` is unix SECONDS -- the serializer emits `created_at.to_i`.
//
// This read `messageStamp(new Date(seconds), 'LLL d, yyyy')`, which happens to produce the right
// instant only because building a Date from seconds-as-milliseconds and then multiplying by 1000
// cancels out exactly. The value was right by coincidence; the FORMAT was a hardcoded English
// pattern with no locale, so an Arabic screen read "Oct 15, 2025" in the middle of Arabic text.
const toDate = seconds => new Date(seconds * 1000);

const readableDate = seconds =>
  new Intl.DateTimeFormat(locale.value, { dateStyle: 'medium' }).format(
    toDate(seconds)
  );

const readableDateWithTime = seconds =>
  new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(toDate(seconds));

// 'Runs after 3d' became 'Runs after 3 days' in whichever language is on, because 'd' is not a word
// in Arabic and was not one to a lot of English readers either.
const delayLabel = computed(() => {
  const { value, unit } = formatDelay(props.automation.execution_delay);
  return t(`AUTOMATION.LIST.DELAY_BADGE_${unit}`, { count: value });
});

const automationActive = computed({
  get: () => props.automation.active,
  set: active => {
    const { id, name } = props.automation;
    emit('toggle', {
      id,
      name,
      status: !active,
    });
  },
});
</script>

<template>
  <BaseTableRow :item="automation">
    <template #default>
      <BaseTableCell class="max-w-0 w-full">
        <div
          class="flex flex-col sm:flex-row sm:items-center gap-0.5 sm:gap-2 min-w-0"
        >
          <div
            class="flex items-center gap-2 min-w-0 sm:shrink-0 sm:max-w-[65%]"
          >
            <span class="text-body-main text-n-slate-12 truncate">
              {{ automation.name }}
            </span>
            <WootLabel
              v-if="automation.execution_delay"
              compact
              variant="subtle"
              :label="delayLabel"
            />
          </div>
          <div class="hidden sm:block w-px h-3 rounded-lg bg-n-weak shrink-0" />
          <span
            class="text-body-main text-n-slate-11 truncate sm:min-w-0 sm:flex-1"
          >
            {{ automation.description }}
          </span>
        </div>
        <!-- What the hidden column says, where it says it on a phone. -->
        <span
          class="block md:hidden mt-1 text-label-small text-n-slate-11 whitespace-nowrap"
          :title="readableDateWithTime(automation.created_on)"
        >
          {{ readableDate(automation.created_on) }}
        </span>
      </BaseTableCell>

      <BaseTableCell>
        <!-- Icon-only controls carry their own name: a row of unlabelled switches is a row of
        "toggle button" to a screen reader, with nothing to say WHICH rule each one turns off. -->
        <ToggleSwitch
          v-model="automationActive"
          :aria-label="
            t('AUTOMATION.LIST.TOGGLE_ARIA_LABEL', { name: automation.name })
          "
        />
      </BaseTableCell>

      <BaseTableCell
        class="hidden md:table-cell"
        :title="readableDateWithTime(automation.created_on)"
      >
        <span class="text-body-main text-n-slate-12 whitespace-nowrap">
          {{ readableDate(automation.created_on) }}
        </span>
      </BaseTableCell>

      <BaseTableCell align="end">
        <div class="flex gap-3 justify-end flex-shrink-0">
          <Button
            v-tooltip.top="$t('AUTOMATION.FORM.EDIT')"
            :aria-label="$t('AUTOMATION.FORM.EDIT')"
            icon="i-woot-edit-pen"
            slate
            sm
            :is-loading="loading"
            @click="$emit('edit', automation)"
          />
          <Button
            v-tooltip.top="$t('AUTOMATION.CLONE.TOOLTIP')"
            :aria-label="$t('AUTOMATION.CLONE.TOOLTIP')"
            icon="i-woot-clone"
            sm
            slate
            :is-loading="loading"
            @click="$emit('clone', automation)"
          />
          <Button
            v-tooltip.top="$t('AUTOMATION.FORM.DELETE')"
            :aria-label="$t('AUTOMATION.FORM.DELETE')"
            :is-loading="loading"
            icon="i-woot-bin"
            slate
            sm
            class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
            @click="$emit('delete', automation)"
          />
        </div>
      </BaseTableCell>
    </template>
  </BaseTableRow>
</template>
