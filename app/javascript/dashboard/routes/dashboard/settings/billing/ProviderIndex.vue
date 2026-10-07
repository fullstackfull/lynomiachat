<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

import StripeBilling from './Index.vue';
import SettingsLayout from '../SettingsLayout.vue';

// Lynomia bills through its own API (custom/app/controllers/api/v1/accounts/billing_controller.rb), so there is
// one provider here. Chatwoot's Shopify-billed branch is gone with the Enterprise billing identity it read.
const { currentAccount } = useAccount();

const isAccountLoaded = computed(() => Boolean(currentAccount.value?.id));
</script>

<template>
  <SettingsLayout
    v-if="!isAccountLoaded"
    is-loading
    :loading-message="$t('BILLING_SETTINGS.LOADING')"
  />
  <StripeBilling v-else />
</template>
