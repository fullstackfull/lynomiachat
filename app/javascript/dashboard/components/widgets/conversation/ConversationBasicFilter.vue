<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useMapGetter } from 'dashboard/composables/store.js';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  isOnExpandedLayout: {
    type: Boolean,
    required: true,
  },
  showStatusFilter: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['changeFilter']);

const { t } = useI18n();

const chatStatusFilter = useMapGetter('getChatStatusFilter');
const chatSortFilter = useMapGetter('getChatSortFilter');

const [showActionsDropdown, toggleDropdown] = useToggle();

const chatStatusOptions = computed(() => [
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.open.TEXT'),
    value: 'open',
  },
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.resolved.TEXT'),
    value: 'resolved',
  },
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.pending.TEXT'),
    value: 'pending',
  },
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.snoozed.TEXT'),
    value: 'snoozed',
  },
  {
    label: t('CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.all.TEXT'),
    value: 'all',
  },
]);

const chatSortOptions = computed(() => [
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.last_activity_at_asc.TEXT'),
    value: 'last_activity_at_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.last_activity_at_desc.TEXT'),
    value: 'last_activity_at_desc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.created_at_desc.TEXT'),
    value: 'created_at_desc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.created_at_asc.TEXT'),
    value: 'created_at_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.unread.TEXT'),
    value: 'unread',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.priority_desc.TEXT'),
    value: 'priority_desc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.priority_asc.TEXT'),
    value: 'priority_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.priority_desc_created_at_asc.TEXT'),
    value: 'priority_desc_created_at_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.waiting_since_asc.TEXT'),
    value: 'waiting_since_asc',
  },
  {
    label: t('CHAT_LIST.SORT_ORDER_ITEMS.waiting_since_desc.TEXT'),
    value: 'waiting_since_desc',
  },
]);

// The panel holds the status filter as well as the sort order, so the trigger has to say so: naming it
// "Sort conversations" is what hid the status filter from everyone who never thought to look under sorting.
const triggerLabel = computed(() =>
  props.showStatusFilter
    ? t('CHAT_LIST.FILTER_AND_SORT_TOOLTIP_LABEL')
    : t('CHAT_LIST.SORT_TOOLTIP_LABEL')
);

const activeChatStatusLabel = computed(
  () =>
    chatStatusOptions.value.find(m => m.value === chatStatusFilter.value)
      ?.label || ''
);

const activeChatSortLabel = computed(
  () =>
    chatSortOptions.value.find(m => m.value === chatSortFilter.value)?.label ||
    ''
);

// The status filter is reachable from two places now -- this panel and the header chip that names it -- so
// applying it, mirroring it into the store and persisting the pair all live with the list that owns both
// halves (ChatList.onBasicFilterChange). This panel only reports the choice.
const changeFilter = (value, type) => {
  emit('changeFilter', value, type);
};

// The header's status chip opens this same panel, so there is one status control rather than two.
const openDropdown = () => {
  showActionsDropdown.value = true;
};

defineExpose({ openDropdown });
</script>

<template>
  <div class="relative flex">
    <NextButton
      v-tooltip.right="triggerLabel"
      :aria-label="triggerLabel"
      icon="i-lucide-arrow-up-down"
      slate
      faded
      xs
      @click="toggleDropdown()"
    />
    <div
      v-if="showActionsDropdown"
      v-on-click-outside="() => toggleDropdown()"
      class="mt-1 bg-n-alpha-3 backdrop-blur-panel border border-n-weak w-72 rounded-overlay p-4 absolute z-dropdown top-full"
      :class="{
        'ltr:left-0 rtl:right-0': !isOnExpandedLayout,
        'ltr:right-0 rtl:left-0': isOnExpandedLayout,
      }"
    >
      <div
        v-if="showStatusFilter"
        class="flex items-center justify-between gap-2"
      >
        <span class="text-sm truncate text-n-slate-12">
          {{ $t('CHAT_LIST.CHAT_SORT.STATUS') }}
        </span>
        <SelectMenu
          :model-value="chatStatusFilter"
          :options="chatStatusOptions"
          :label="activeChatStatusLabel"
          :sub-menu-position="isOnExpandedLayout ? 'left' : 'right'"
          @update:model-value="value => changeFilter(value, 'status')"
        />
      </div>
      <div
        class="flex items-center justify-between gap-2"
        :class="{ 'mt-4': showStatusFilter }"
      >
        <span class="text-sm truncate text-n-slate-12">
          {{ $t('CHAT_LIST.CHAT_SORT.ORDER_BY') }}
        </span>
        <SelectMenu
          :model-value="chatSortFilter"
          :options="chatSortOptions"
          :label="activeChatSortLabel"
          :sub-menu-position="isOnExpandedLayout ? 'left' : 'right'"
          @update:model-value="value => changeFilter(value, 'sort')"
        />
      </div>
    </div>
  </div>
</template>
