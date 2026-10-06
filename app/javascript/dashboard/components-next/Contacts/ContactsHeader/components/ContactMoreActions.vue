<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';
import {
  AUDIENCE_AUTOMATION_ROUTE,
  AUDIENCE_CAMPAIGN_ROUTE,
} from 'dashboard/helper/audienceHelper';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  // The audience being viewed, when the list is one (`contacts_dashboard_segments_index`). Its actions belong in this
  // menu rather than in more header buttons.
  segment: { type: Object, default: null },
  // The label the list is filtered by, when it is one. A label is a campaign recipient source in its own right.
  activeLabel: { type: Object, default: null },
});

const emit = defineEmits([
  'add',
  'import',
  'export',
  'duplicateSegment',
  'useInAutomation',
  'useInCampaign',
  'copySegmentLink',
  'audiencePreset',
]);

const { t } = useI18n();
const router = useRouter();
const { checkPermissions, checkInstallationType, isFeatureFlagEnabled } =
  usePolicy();
const currentAccountId = useMapGetter('getCurrentAccountId');

const canManageContacts = computed(() =>
  checkPermissions(['administrator', 'contact_manage'])
);

// Only a shared audience can be referenced by an automation rule or a campaign, so those two actions appear only
// where they would work. Whether the target page is reachable is that route's own answer, asked exactly as the
// command bar asks it: a shortcut must never offer a page the page itself would refuse.
const isShared = computed(() => Boolean(props.segment?.shared));

const canReach = routeName => {
  const { meta } = router.resolve({
    name: routeName,
    params: { accountId: currentAccountId.value },
  });
  return (
    isFeatureFlagEnabled(meta?.featureFlag) &&
    checkPermissions(meta?.permissions) &&
    checkInstallationType(meta?.installationTypes)
  );
};

// A shared audience that automation rules or campaigns still to send reference cannot be deleted or made personal.
// That was only visible inside the condition editor; it belongs where the audience is acted on.
const usageLabel = computed(() => {
  const rules = props.segment?.active_automation_rules_count || 0;
  const campaigns = props.segment?.campaigns_count || 0;
  if (!rules && !campaigns) return '';

  const parts = [];
  if (rules) {
    parts.push(
      t(
        'CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.USED_BY_RULES',
        { n: rules },
        rules
      )
    );
  }
  if (campaigns) {
    parts.push(
      t(
        'CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.USED_BY_CAMPAIGNS',
        { n: campaigns },
        campaigns
      )
    );
  }
  return t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.USED_BY', {
    usage: parts.join(' · '),
  });
});

const segmentActions = computed(() => {
  return [
    ...(usageLabel.value
      ? [
          {
            label: usageLabel.value,
            value: 'segment-usage',
            icon: 'i-lucide-link',
            disabled: true,
          },
        ]
      : []),
    ...(isShared.value && canReach(AUDIENCE_AUTOMATION_ROUTE)
      ? [
          {
            label: t(
              'CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.USE_IN_AUTOMATION'
            ),
            action: 'useInAutomation',
            value: 'use-in-automation',
            icon: 'i-lucide-repeat',
          },
        ]
      : []),
    ...(isShared.value && canReach(AUDIENCE_CAMPAIGN_ROUTE)
      ? [
          {
            label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.USE_IN_CAMPAIGN'),
            action: 'useInCampaign',
            value: 'use-in-campaign',
            icon: 'i-lucide-megaphone',
          },
        ]
      : []),
    ...(canManageContacts.value
      ? [
          {
            label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.DUPLICATE'),
            action: 'duplicateSegment',
            value: 'duplicate-segment',
            icon: 'i-lucide-copy',
          },
        ]
      : []),
    {
      label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.COPY_LINK'),
      action: 'copySegmentLink',
      value: 'copy-segment-link',
      icon: 'i-lucide-link-2',
    },
  ];
});

// A label page's actions. "Use in a new WhatsApp campaign" only: `Campaign#audience_contacts` resolves
// `{ type: 'Label', id }`, so a label genuinely is a recipient source. There is deliberately no "use in a new
// automation rule" beside it — the one audience-shaped automation condition is `contact_audience`, which names a
// shared audience, and no condition means "the contact carries label X". Offering it for symmetry would open a
// rule builder that cannot express what the menu implied.
const labelActions = computed(() => {
  if (!props.activeLabel || !canReach(AUDIENCE_CAMPAIGN_ROUTE)) return [];

  return [
    {
      label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.USE_IN_CAMPAIGN'),
      action: 'useInCampaign',
      value: 'use-in-campaign',
      icon: 'i-lucide-megaphone',
    },
  ];
});

const audienceItems = computed(() => {
  const segmentItems = props.segment
    ? segmentActions.value
    : labelActions.value;
  return [
    ...segmentItems,
    {
      label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.FROM_PRESET'),
      action: 'audiencePreset',
      value: 'audience-preset',
      icon: 'i-lucide-sparkles',
    },
  ];
});

const contactItems = computed(() => [
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.ADD_CONTACT'),
    action: 'add',
    value: 'add',
    icon: 'i-lucide-plus',
  },
  ...(canManageContacts.value
    ? [
        {
          label: t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.EXPORT_CONTACT'
          ),
          action: 'export',
          value: 'export',
          icon: 'i-lucide-upload',
        },
        {
          label: t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.IMPORT_CONTACT'
          ),
          action: 'import',
          value: 'import',
          icon: 'i-lucide-download',
        },
      ]
    : []),
]);

const menuSections = computed(() => [
  {
    title: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.SECTION'),
    items: audienceItems.value,
  },
  { items: contactItems.value },
]);

const showActionsDropdown = ref(false);

const handleContactAction = ({ action }) => {
  showActionsDropdown.value = false;
  if (action === 'add') emit('add');
  else if (action === 'import') emit('import');
  else if (action === 'export') emit('export');
  else if (action === 'duplicateSegment') emit('duplicateSegment');
  else if (action === 'useInAutomation') emit('useInAutomation');
  else if (action === 'useInCampaign') emit('useInCampaign');
  else if (action === 'copySegmentLink') emit('copySegmentLink');
  else if (action === 'audiencePreset') emit('audiencePreset');
};
</script>

<template>
  <div v-on-clickaway="() => (showActionsDropdown = false)" class="relative">
    <Button
      icon="i-lucide-ellipsis-vertical"
      color="slate"
      variant="ghost"
      size="sm"
      :aria-label="t('CONTACTS_LAYOUT.HEADER.ACTIONS.MORE')"
      :class="showActionsDropdown ? 'bg-n-alpha-2' : ''"
      data-test-id="contact-more-actions"
      @click="showActionsDropdown = !showActionsDropdown"
    />
    <DropdownMenu
      v-if="showActionsDropdown"
      :menu-sections="menuSections"
      class="ltr:right-0 rtl:left-0 mt-1 w-60 top-full"
      @action="handleContactAction($event)"
    />
  </div>
</template>
