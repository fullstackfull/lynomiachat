<script setup>
import { computed } from 'vue';
import { messageStamp } from 'shared/helpers/timeHelper';
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

const readableDate = date => messageStamp(new Date(date), 'LLL d, yyyy');
const readableDateWithTime = date =>
  messageStamp(new Date(date), 'LLL d, yyyy hh:mm a');

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
              :label="
                $t('AUTOMATION.LIST.DELAY_BADGE', {
                  delay: formatDelay(automation.execution_delay),
                })
              "
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
        <ToggleSwitch v-model="automationActive" />
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
