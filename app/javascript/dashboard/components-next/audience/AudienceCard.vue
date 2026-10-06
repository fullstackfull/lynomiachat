<script setup>
// One audience, on the Audiences page (docs/product-enablement/13-audience-ux-implementation.md).
//
// Everything on this card except the contact count is read from the record the store already holds: the name, whether
// it is shared, the conditions it asks for, and how many automation rules and unsent campaigns depend on it. So a page
// of audiences costs one request and asks no provider anything. The count is the one thing that needs evaluating, so
// it is a button: nobody pays for a number they did not ask for.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { useMapGetter } from 'dashboard/composables/store';
import { summariseAudience } from 'dashboard/helper/audienceSummary';
import {
  AUDIENCE_AUTOMATION_ROUTE,
  AUDIENCE_CAMPAIGN_ROUTE,
} from 'dashboard/helper/audienceHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  audience: { type: Object, required: true },
  // Both filter vocabularies, so a summary can name a Commerce or Conversation condition as well as a contact one.
  filterTypes: { type: Array, default: () => [] },
  // The contacts this audience selects now, once somebody has asked. `null` until then.
  count: { type: Number, default: null },
  isCounting: { type: Boolean, default: false },
});

const emit = defineEmits([
  'open',
  'edit',
  'duplicate',
  'useInAutomation',
  'useInCampaign',
  'copyLink',
  'delete',
  'count',
]);

// Beyond three conditions a one-line summary stops being readable, so the rest are counted instead.
const SUMMARY_CONDITION_LIMIT = 3;

const { t } = useI18n();
const router = useRouter();
const { isAdmin } = useAdmin();
const { checkPermissions, checkInstallationType, isFeatureFlagEnabled } =
  usePolicy();
const currentAccountId = useMapGetter('getCurrentAccountId');

const isShared = computed(() => Boolean(props.audience.shared));
// A shared audience belongs to the account: administrators change and delete it. A personal one is the user's own —
// the index returns nobody else's — so they may always manage it. The server enforces both; this only stops the UI
// offering an action it would refuse.
const canManage = computed(() => !isShared.value || isAdmin.value);

// Asked exactly as the audience overflow menu in the Contacts header asks it: a shortcut must never offer a page the
// page itself would refuse.
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

const summary = computed(() =>
  summariseAudience(props.audience.query, props.filterTypes, {
    limit: SUMMARY_CONDITION_LIMIT,
    andLabel: t('CONTACTS_FILTER.QUERY_DROPDOWN_LABELS.AND').toLowerCase(),
    moreLabel: count =>
      t('CAMPAIGN.RECIPIENTS.AUDIENCES.CONDITIONS', { count }, count),
  })
);

// What depends on this audience, which is also what keeps it from being deleted or made personal. Counted by the
// server and already on the record; only shared audiences can be depended on.
const usage = computed(() => {
  const rules = props.audience.active_automation_rules_count || 0;
  const campaigns = props.audience.campaigns_count || 0;
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

const menuItems = computed(() => [
  {
    label: t('CONTACTS_LAYOUT.AUDIENCES.ACTIONS.OPEN'),
    action: 'open',
    value: 'open',
    icon: 'i-lucide-users-round',
  },
  ...(canManage.value
    ? [
        {
          label: t('CONTACTS_LAYOUT.AUDIENCES.ACTIONS.EDIT'),
          action: 'edit',
          value: 'edit',
          icon: 'i-lucide-pen-line',
        },
      ]
    : []),
  ...(isShared.value && canReach(AUDIENCE_AUTOMATION_ROUTE)
    ? [
        {
          label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.USE_IN_AUTOMATION'),
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
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.DUPLICATE'),
    action: 'duplicate',
    value: 'duplicate',
    icon: 'i-lucide-copy',
  },
  {
    label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.AUDIENCE.COPY_LINK'),
    action: 'copyLink',
    value: 'copy-link',
    icon: 'i-lucide-link-2',
  },
  ...(canManage.value
    ? [
        {
          label: t('CONTACTS_LAYOUT.AUDIENCES.ACTIONS.DELETE'),
          action: 'delete',
          value: 'delete',
          icon: 'i-lucide-trash',
        },
      ]
    : []),
]);

const showMenu = ref(false);

// Named one by one rather than re-emitting whatever the menu item carried: the card's contract is these eight
// events, not whatever string a future menu entry happens to use.
const handleAction = ({ action }) => {
  showMenu.value = false;
  if (action === 'open') emit('open');
  else if (action === 'edit') emit('edit');
  else if (action === 'duplicate') emit('duplicate');
  else if (action === 'useInAutomation') emit('useInAutomation');
  else if (action === 'useInCampaign') emit('useInCampaign');
  else if (action === 'copyLink') emit('copyLink');
  else if (action === 'delete') emit('delete');
};
</script>

<template>
  <div
    class="flex flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    data-test-id="audience-card"
  >
    <div class="flex items-start justify-between gap-3">
      <div class="flex flex-wrap items-center gap-2 min-w-0">
        <Button
          variant="link"
          color="slate"
          size="sm"
          class="!p-0 !h-auto text-base font-medium !text-n-slate-12 truncate"
          :label="audience.name"
          @click="emit('open')"
        />
        <Label
          :label="
            isShared
              ? t('CONTACTS_LAYOUT.AUDIENCES.SHARED')
              : t('CONTACTS_LAYOUT.AUDIENCES.PERSONAL')
          "
          :tone="isShared ? 'info' : 'neutral'"
          variant="subtle"
          compact
        />
      </div>
      <div v-on-clickaway="() => (showMenu = false)" class="relative shrink-0">
        <Button
          icon="i-lucide-ellipsis-vertical"
          color="slate"
          variant="ghost"
          size="sm"
          :aria-label="
            t('CONTACTS_LAYOUT.AUDIENCES.ACTIONS.MORE', {
              name: audience.name,
            })
          "
          :class="showMenu ? 'bg-n-alpha-2' : ''"
          @click="showMenu = !showMenu"
        />
        <DropdownMenu
          v-if="showMenu"
          :menu-items="menuItems"
          class="ltr:right-0 rtl:left-0 mt-1 w-60 top-full"
          @action="handleAction($event)"
        />
      </div>
    </div>

    <p v-if="summary" class="mb-0 text-label-small text-n-slate-11">
      {{ summary }}
    </p>
    <p v-else class="mb-0 text-label-small text-n-slate-11 italic">
      {{ t('CONTACTS_LAYOUT.AUDIENCES.NO_CONDITIONS') }}
    </p>

    <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
      <!-- The number nobody pays for unless they ask. Once asked, it stays on the card. -->
      <span
        v-if="count !== null"
        class="flex items-center gap-1.5 text-label-small text-n-slate-12"
        data-test-id="audience-count"
      >
        <Icon
          icon="i-lucide-users-round"
          class="size-3.5 text-n-slate-11"
          aria-hidden="true"
        />
        {{ t('CONTACTS_LAYOUT.AUDIENCES.COUNT', { count }, count) }}
      </span>
      <Button
        v-else
        variant="link"
        color="slate"
        size="sm"
        class="!p-0 !h-auto"
        icon="i-lucide-users-round"
        :label="t('CONTACTS_LAYOUT.AUDIENCES.COUNT_ACTION')"
        :is-loading="isCounting"
        :disabled="isCounting"
        @click="emit('count')"
      />
      <span
        v-if="usage"
        class="flex items-center gap-1.5 text-label-small text-n-slate-11"
      >
        <Icon
          icon="i-lucide-link"
          class="size-3.5 shrink-0"
          aria-hidden="true"
        />
        {{ usage }}
      </span>
    </div>
  </div>
</template>
