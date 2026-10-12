<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

import SubscriptionSettings from '../subscription/Index.vue';
import SettingsLayout from '../SettingsLayout.vue';

// Lynomia (docs/p11/06-rollout-compatibility.md). Settings -> Billing now shows this installation's own
// billing page, which is the one that works.
//
// It used to render a component whose entire body was
//   onMounted(() => { window.location.href = `https://lynomia.com/admin/subscriptions/${accountId}` })
// -- a hard redirect to a hardcoded external domain, carrying the account id in the path. Thirteen surfaces
// link here: the sidebar, PaymentPendingBanner, the suspended page, five paywalls and both upgrade pages. On
// a self-hosted installation every one of them sent the customer to somebody else's host, while the billing
// page that actually works sat behind a second, less prominent sidebar entry. Both routes now reach the same
// page, so none of those thirteen links had to change and none of them leaves the product.
//
// The wait below is kept: the billing API is account-scoped, so mounting it before the account is loaded
// would address the wrong account.
const { currentAccount } = useAccount();

const isAccountLoaded = computed(() => Boolean(currentAccount.value?.id));
</script>

<template>
  <SettingsLayout
    v-if="!isAccountLoaded"
    is-loading
    :loading-message="$t('BILLING_SETTINGS.LOADING')"
  />
  <SubscriptionSettings v-else />
</template>
