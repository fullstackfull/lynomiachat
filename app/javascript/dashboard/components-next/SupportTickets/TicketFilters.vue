<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { startOfDay, endOfDay } from 'date-fns';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';
import {
  TICKET_ASSIGNEE_ME,
  TICKET_ASSIGNEE_UNASSIGNED,
  TICKET_CATEGORIES,
  TICKET_DEFAULT_SORT,
  TICKET_PRIORITIES,
  TICKET_SLA_STATES,
  TICKET_SORTS,
  TICKET_STATUSES,
} from 'dashboard/constants/supportTickets';

// The workspace's filter bar, built the way the audit log reader's is: one dropdown per dimension, each one
// labelled with what is currently selected, and every change emitted as a partial query the page pushes. The
// URL stays the single source of truth, so nothing here holds state the address bar does not.
const props = defineProps({
  // The filters as read from the route query.
  filters: {
    type: Object,
    required: true,
  },
  // The picker's named range (`last_7_days` and friends), kept in the URL so a reload reopens the same preset.
  range: {
    type: String,
    default: '',
  },
  agents: {
    type: Array,
    default: () => [],
  },
  teams: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();

const MILLISECONDS_PER_SECOND = 1000;

const toUnixTime = date => Math.floor(date.getTime() / MILLISECONDS_PER_SECOND);
const toDate = seconds => new Date(seconds * MILLISECONDS_PER_SECOND);
const isKnownRange = value => Object.values(DATE_RANGE_TYPES).includes(value);

const openFilterMenu = ref(null);
const showPicker = ref(false);

const pickerKey = ref(0);
const pickerDateRange = ref([]);
const pickerRangeType = ref(DATE_RANGE_TYPES.LAST_7_DAYS);

const hasDateFilter = computed(() =>
  Boolean(props.filters.since && props.filters.until)
);
const isPickerVisible = computed(() => hasDateFilter.value || showPicker.value);

watch(
  () => [props.range, props.filters.since, props.filters.until],
  () => {
    if (!hasDateFilter.value) {
      showPicker.value = false;
      return;
    }
    pickerRangeType.value = isKnownRange(props.range)
      ? props.range
      : DATE_RANGE_TYPES.CUSTOM_RANGE;
    pickerDateRange.value = [
      toDate(props.filters.since),
      toDate(props.filters.until),
    ];
  },
  { immediate: true }
);

// One section per menu: an "any" entry that clears the filter, then the values. The selected entry's label is
// what the trigger button shows, so the bar reads as a sentence rather than as six identical chevrons.
const enumSection = (filterKey, values, translationPrefix, anyLabel) => [
  {
    items: [
      {
        label: anyLabel,
        action: filterKey,
        isSelected: !props.filters[filterKey],
      },
      ...values.map(value => ({
        label: t(`${translationPrefix}.${value.toUpperCase()}`),
        value,
        action: filterKey,
        isSelected: props.filters[filterKey] === value,
      })),
    ],
  },
];

const assigneeSections = computed(() => [
  {
    items: [
      {
        label: t('SUPPORT_TICKETS.FILTERS.ANY_ASSIGNEE'),
        action: 'assignee_id',
        isSelected: !props.filters.assignee_id,
      },
      {
        label: t('SUPPORT_TICKETS.FILTERS.ASSIGNEE.ME'),
        value: TICKET_ASSIGNEE_ME,
        action: 'assignee_id',
        isSelected: props.filters.assignee_id === TICKET_ASSIGNEE_ME,
      },
      {
        label: t('SUPPORT_TICKETS.FILTERS.ASSIGNEE.UNASSIGNED'),
        value: TICKET_ASSIGNEE_UNASSIGNED,
        action: 'assignee_id',
        isSelected: props.filters.assignee_id === TICKET_ASSIGNEE_UNASSIGNED,
      },
    ],
  },
  {
    title: t('SUPPORT_TICKETS.FILTERS.GROUPS.AGENTS'),
    items: props.agents.map(agent => ({
      label: agent.name,
      value: agent.id,
      action: 'assignee_id',
      isSelected: props.filters.assignee_id === agent.id,
    })),
  },
]);

const teamSections = computed(() => [
  {
    items: [
      {
        label: t('SUPPORT_TICKETS.FILTERS.ANY_TEAM'),
        action: 'team_id',
        isSelected: !props.filters.team_id,
      },
      ...props.teams.map(team => ({
        label: team.name,
        value: team.id,
        action: 'team_id',
        isSelected: props.filters.team_id === team.id,
      })),
    ],
  },
]);

const sortSections = computed(() => [
  {
    items: TICKET_SORTS.map(sort => ({
      label: t(`SUPPORT_TICKETS.FILTERS.SORT.${sort.toUpperCase()}`),
      // The default sort is the absence of a `sort` parameter, so choosing it clears the key.
      value: sort === TICKET_DEFAULT_SORT ? undefined : sort,
      action: 'sort',
      isSelected: (props.filters.sort || TICKET_DEFAULT_SORT) === sort,
    })),
  },
]);

const filterMenus = computed(() =>
  [
    {
      key: 'status',
      icon: 'i-lucide-circle-dot',
      sections: enumSection(
        'status',
        TICKET_STATUSES,
        'SUPPORT_TICKETS.ENUMS.STATUS',
        t('SUPPORT_TICKETS.FILTERS.ANY_STATUS')
      ),
    },
    {
      key: 'priority',
      icon: 'i-lucide-flag',
      sections: enumSection(
        'priority',
        TICKET_PRIORITIES,
        'SUPPORT_TICKETS.ENUMS.PRIORITY',
        t('SUPPORT_TICKETS.FILTERS.ANY_PRIORITY')
      ),
    },
    {
      key: 'category',
      icon: 'i-lucide-tag',
      sections: enumSection(
        'category',
        TICKET_CATEGORIES,
        'SUPPORT_TICKETS.ENUMS.CATEGORY',
        t('SUPPORT_TICKETS.FILTERS.ANY_CATEGORY')
      ),
    },
    {
      key: 'assignee_id',
      icon: 'i-lucide-user-round',
      sections: assigneeSections.value,
    },
    { key: 'team_id', icon: 'i-lucide-users', sections: teamSections.value },
    {
      key: 'sla',
      icon: 'i-lucide-timer',
      sections: enumSection(
        'sla',
        TICKET_SLA_STATES,
        'SUPPORT_TICKETS.FILTERS.SLA',
        t('SUPPORT_TICKETS.FILTERS.ANY_SLA')
      ),
    },
    {
      key: 'sort',
      icon: 'i-lucide-arrow-down-up',
      sections: sortSections.value,
    },
  ].map(menu => ({
    ...menu,
    label: menu.sections
      .flatMap(section => section.items)
      .find(item => item.isSelected)?.label,
  }))
);

const resetPicker = () => {
  if (hasDateFilter.value) pickerKey.value += 1;
  else showPicker.value = false;
};

const closeMenus = () => {
  openFilterMenu.value = null;
};

const closeFilterMenu = () => {
  closeMenus();
  resetPicker();
};

const openDatePicker = () => {
  closeMenus();
  showPicker.value = true;
};

const toggleFilterMenu = key => {
  resetPicker();
  openFilterMenu.value = openFilterMenu.value === key ? null : key;
};

const applyDateRange = ([start, end, range]) => {
  emit('update', {
    range,
    since: toUnixTime(startOfDay(start)),
    until: toUnixTime(endOfDay(end)),
  });
};

const handleFilterAction = ({ action, value }) => {
  closeFilterMenu();
  emit('update', { [action]: value });
};
</script>

<template>
  <div
    v-on-click-outside="closeFilterMenu"
    class="flex flex-wrap items-center gap-2 min-w-0"
  >
    <WootDatePicker
      v-if="isPickerVisible"
      :key="pickerKey"
      v-model:date-range="pickerDateRange"
      v-model:range-type="pickerRangeType"
      :has-applied-range="hasDateFilter"
      @click="closeMenus"
      @close="resetPicker"
      @date-range-changed="applyDateRange"
    />
    <Button
      v-else
      :label="t('SUPPORT_TICKETS.FILTERS.DATE_RANGE')"
      icon="i-lucide-calendar-range"
      color="slate"
      size="sm"
      @click="openDatePicker"
    />
    <div v-for="menu in filterMenus" :key="menu.key" class="relative">
      <Button
        :icon="menu.icon"
        color="slate"
        size="sm"
        :class="{ 'bg-n-slate-9/10': openFilterMenu === menu.key }"
        aria-haspopup="menu"
        :aria-expanded="openFilterMenu === menu.key"
        @click="toggleFilterMenu(menu.key)"
      >
        <span class="min-w-0 truncate">{{ menu.label }}</span>
        <Icon icon="i-lucide-chevron-down" class="shrink-0 size-4" />
      </Button>
      <DropdownMenu
        v-if="openFilterMenu === menu.key"
        :menu-sections="menu.sections"
        class="mt-2 min-w-52 max-h-80 top-full start-0"
        @action="handleFilterAction"
      />
    </div>
  </div>
</template>
