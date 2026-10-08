<script setup>
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

// Custom roles are Lynomia's own feature (custom/app/models/custom_role.rb), gated by the
// `custom_roles` account flag and sold through Lynomia's plans -- so an unentitled account needs a
// plan notice, not Chatwoot's "switch to Enterprise edition" advert. Same inline pattern the
// Commerce settings page uses for its store limit.
const route = useRoute();
const { t } = useI18n();
</script>

<template>
  <p
    class="flex flex-wrap items-center gap-x-2 gap-y-1 rounded-lg bg-n-amber-2 px-3 py-2 text-body-main text-n-amber-11"
  >
    {{ t('CUSTOM_ROLE.PLAN_NOTICE.TEXT') }}
    <router-link
      :to="{
        name: 'subscription_settings_index',
        params: { accountId: route.params.accountId },
      }"
      class="font-medium underline"
    >
      {{ t('CUSTOM_ROLE.PLAN_NOTICE.VIEW_PLANS') }}
    </router-link>
  </p>
</template>
