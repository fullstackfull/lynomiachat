<script setup>
import { onMounted, computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { CONTACT_PERMISSIONS } from 'dashboard/constants/permissions';

import ContactsDetailsLayout from 'dashboard/components-next/Contacts/ContactsDetailsLayout.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactDetails from 'dashboard/components-next/Contacts/Pages/ContactDetails.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ContactNotes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactNotes.vue';
import ContactHistory from 'dashboard/components-next/Contacts/ContactsSidebar/ContactHistory.vue';
import ContactActivity from 'dashboard/components-next/Contacts/ContactsSidebar/ContactActivity.vue';
import ContactCases from 'dashboard/components-next/Contacts/ContactsSidebar/ContactCases.vue';
import ContactMedia from 'dashboard/components-next/Contacts/ContactsSidebar/ContactMedia.vue';
import ContactMerge from 'dashboard/components-next/Contacts/ContactsSidebar/ContactMerge.vue';
import ContactCustomAttributes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactCustomAttributes.vue';
import ContactIdentities from 'dashboard/components-next/Contacts/ContactsSidebar/ContactIdentities.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();

const contact = useMapGetter('contacts/getContactById');
const uiFlags = useMapGetter('contacts/getUIFlags');

const activeTab = ref('attributes');
const contactMergeRef = ref(null);

const isFetchingItem = computed(() => uiFlags.value.isFetchingItem);
const isMergingContact = computed(() => uiFlags.value.isMerging);
const isUpdatingContact = computed(() => uiFlags.value.isUpdating);

const selectedContact = computed(() => contact.value(route.params.contactId));

const showSpinner = computed(
  () => isFetchingItem.value || isMergingContact.value
);

const { t } = useI18n();

const { isCloudFeatureEnabled } = useAccount();
const { checkPermissions } = usePolicy();

const isSupportTicketsEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LYNOMIA_SUPPORT_TICKETS)
);

// The identities tab, like the cases tab, stays out of the list entirely when the account does not have the
// feature: the endpoint answers 404 for such an account, so an always-present tab would only ever fail.
const isUnifiedIdentityEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LYNOMIA_UNIFIED_IDENTITY)
);

// Linking decides where the next message carrying a number is delivered, so it follows the merge boundary --
// administrator, or an agent whose custom role grants contact management. Reading the list does not; everyone
// who may open the contact sees it, which is why this gates the controls and not the tab.
const canManageIdentities = computed(() =>
  checkPermissions(['administrator', CONTACT_PERMISSIONS])
);

// `when` is how a tab that depends on an account feature stays out of the list entirely rather than rendering
// an error the moment it is opened: the support endpoints answer 404 for an account without the module, so an
// always-present Cases tab would be a tab that only ever fails.
const CONTACT_TABS_OPTIONS = [
  { key: 'ATTRIBUTES', value: 'attributes' },
  // The unified activity timeline (docs/p8/03-contact-activity-timeline.md). It sits beside History rather than
  // replacing it: History is the contact's conversation list, this is everything that happened in order.
  { key: 'ACTIVITY', value: 'activity' },
  // This contact's support cases (docs/p9/02-support-tickets.md). Beside Activity rather than inside it: the
  // timeline says what happened, this says what is still open and who owns it.
  { key: 'CASES', value: 'cases', when: isSupportTicketsEnabled },
  // Everything this customer can be reached at (docs/p10/05-omnichannel-customer-360.md). Beside History
  // rather than inside Attributes: an attribute is a field on the record, this is the set of values that
  // resolve to the record.
  { key: 'IDENTITIES', value: 'identities', when: isUnifiedIdentityEnabled },
  { key: 'HISTORY', value: 'history' },
  { key: 'NOTES', value: 'notes' },
  { key: 'MEDIA', value: 'media' },
  { key: 'MERGE', value: 'merge' },
];

const availableTabs = computed(() =>
  CONTACT_TABS_OPTIONS.filter(tab => tab.when?.value ?? true)
);

const tabs = computed(() => {
  return availableTabs.value.map(tab => ({
    label: t(`CONTACTS_LAYOUT.SIDEBAR.TABS.${tab.key}`),
    value: tab.value,
  }));
});

const activeTabIndex = computed(() => {
  return availableTabs.value.findIndex(v => v.value === activeTab.value);
});

const goToContactsList = () => {
  if (window.history.state?.back || window.history.length > 1) {
    router.back();
  } else {
    router.push(`/app/accounts/${route.params.accountId}/contacts?page=1`);
  }
};

const fetchActiveContact = async () => {
  if (route.params.contactId) {
    await store.dispatch('contacts/show', { id: route.params.contactId });
    await store.dispatch(
      'contacts/fetchContactableInbox',
      route.params.contactId
    );
  }
};

const handleTabChange = tab => {
  activeTab.value = tab.value;
};

const fetchContactNotes = () => {
  const { contactId } = route.params;
  if (contactId) store.dispatch('contactNotes/get', { contactId });
};

const fetchContactConversations = () => {
  const { contactId } = route.params;
  if (contactId) store.dispatch('contactConversations/get', contactId);
};

const fetchAttributes = () => {
  store.dispatch('attributes/get');
};

const toggleContactBlock = async isBlocked => {
  const ALERT_MESSAGES = {
    success: {
      block: t('CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_SUCCESS_MESSAGE'),
      unblock: t('CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_SUCCESS_MESSAGE'),
    },
    error: {
      block: t('CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_ERROR_MESSAGE'),
      unblock: t('CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_ERROR_MESSAGE'),
    },
  };

  try {
    await store.dispatch(`contacts/update`, {
      ...selectedContact.value,
      blocked: !isBlocked,
    });
    useAlert(
      isBlocked ? ALERT_MESSAGES.success.unblock : ALERT_MESSAGES.success.block
    );
  } catch (error) {
    useAlert(
      isBlocked ? ALERT_MESSAGES.error.unblock : ALERT_MESSAGES.error.block
    );
  }
};

onMounted(() => {
  fetchActiveContact();
  fetchContactNotes();
  fetchContactConversations();
  fetchAttributes();
});
</script>

<template>
  <div
    class="flex flex-col justify-between flex-1 h-full m-0 overflow-auto bg-n-surface-1"
  >
    <ContactsDetailsLayout
      :button-label="$t('CONTACTS_LAYOUT.HEADER.SEND_MESSAGE')"
      :selected-contact="selectedContact"
      is-detail-view
      :show-pagination-footer="false"
      :is-updating="isUpdatingContact"
      @go-to-contacts-list="goToContactsList"
      @toggle-block="toggleContactBlock"
    >
      <div
        v-if="showSpinner"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>
      <ContactDetails
        v-else-if="selectedContact"
        :selected-contact="selectedContact"
        @go-to-contacts-list="goToContactsList"
      />
      <template #sidebarHeader>
        <div class="px-6 pt-6 pb-3">
          <TabBar
            :tabs="tabs"
            :initial-active-tab="activeTabIndex"
            class="w-full [&>button]:w-full bg-n-alpha-black2"
            @tab-changed="handleTabChange"
          />
        </div>
      </template>
      <template #sidebar>
        <div
          v-if="isFetchingItem"
          class="flex items-center justify-center py-10 text-n-slate-11"
        >
          <Spinner />
        </div>
        <template v-else>
          <ContactCustomAttributes
            v-if="activeTab === 'attributes'"
            :selected-contact="selectedContact"
          />
          <ContactActivity v-if="activeTab === 'activity'" />
          <ContactCases
            v-if="activeTab === 'cases' && isSupportTicketsEnabled"
          />
          <ContactIdentities
            v-if="activeTab === 'identities'"
            :contact="selectedContact"
            :can-manage="canManageIdentities"
          />
          <ContactNotes v-if="activeTab === 'notes'" />
          <ContactHistory v-if="activeTab === 'history'" />
          <ContactMedia v-if="activeTab === 'media'" />
          <ContactMerge
            v-if="activeTab === 'merge'"
            ref="contactMergeRef"
            :selected-contact="selectedContact"
            @go-to-contacts-list="goToContactsList"
            @reset-tab="handleTabChange(CONTACT_TABS_OPTIONS[0])"
          />
        </template>
      </template>
    </ContactsDetailsLayout>
  </div>
</template>
