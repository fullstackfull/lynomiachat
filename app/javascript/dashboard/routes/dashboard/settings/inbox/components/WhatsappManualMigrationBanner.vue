<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const emit = defineEmits(['start']);
const { t } = useI18n();
const { brandLink } = useBranding();

// These point at upstream Chatwoot's own documentation, which is the right destination only on an upstream
// installation. A branded one gets its configured DOCUMENTATION_URL, and no link at all when it has none.
const UPSTREAM_MANUAL_MIGRATION_GUIDE_URL = 'https://chwt.app/migrate-whatsapp';

const guideUrl = computed(() =>
  brandLink('documentation', UPSTREAM_MANUAL_MIGRATION_GUIDE_URL)
);

const copy = computed(() => ({
  title: t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANUAL_MIGRATION.BANNER.TITLE'),
  description: t(
    'INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANUAL_MIGRATION.BANNER.DESCRIPTION'
  ),
  start: t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANUAL_MIGRATION.BANNER.START'),
  guide: t('INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_MANUAL_MIGRATION.BANNER.GUIDE'),
}));
</script>

<template>
  <Banner color="blue" :action-label="copy.start" @action="emit('start')">
    <div class="flex items-start gap-2">
      <Icon
        icon="i-lucide-info"
        class="flex-shrink-0 mt-0.5 size-4 text-n-blue-11"
      />
      <div class="flex flex-col gap-0.5">
        <span class="font-medium text-n-blue-12">{{ copy.title }}</span>
        <span>
          {{ copy.description }}
          <a
            v-if="guideUrl"
            :href="guideUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="underline link underline-offset-2"
          >
            {{ copy.guide }}
          </a>
        </span>
      </div>
    </div>
  </Banner>
</template>
