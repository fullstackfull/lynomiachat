<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useBranding } from 'shared/composables/useBranding';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import { useCommerceLabels } from 'dashboard/components/widgets/conversation/commerce/useCommerceLabels';

// The first step of "Add store": which platform the store runs on, and how that platform connects. Every platform is
// listed so the merchant finds theirs; those this installation does not offer yet (`providers` from the stores API) are
// shown as not available and cannot be chosen.
const props = defineProps({
  show: { type: Boolean, default: false },
  providers: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'select']);

const { t } = useI18n();
const { installationName } = useBranding();
const { providerName } = useCommerceLabels();
const dialogRef = ref(null);

const options = computed(() =>
  [
    {
      provider: 'woocommerce',
      icon: 'i-lucide-shopping-bag',
      hint: t('COMMERCE.SETTINGS.PICKER.WOOCOMMERCE_HINT'),
    },
    {
      provider: 'salla',
      icon: 'i-lucide-store',
      hint: t('COMMERCE.SETTINGS.PICKER.SALLA_HINT', {
        installationName: installationName.value,
      }),
    },
    {
      provider: 'zid',
      icon: 'i-lucide-store',
      hint: t('COMMERCE.SETTINGS.PICKER.ZID_HINT', {
        installationName: installationName.value,
      }),
    },
    {
      provider: 'shopify',
      icon: 'i-lucide-shopping-cart',
      hint: t('COMMERCE.SETTINGS.PICKER.SHOPIFY_HINT', {
        installationName: installationName.value,
      }),
    },
  ].map(option => ({
    ...option,
    available: props.providers.includes(option.provider),
  }))
);
const hasUnavailable = computed(() =>
  options.value.some(option => !option.available)
);

watch(
  () => props.show,
  show => (show ? dialogRef.value?.open() : dialogRef.value?.close())
);
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('COMMERCE.SETTINGS.PICKER.TITLE')"
    :description="t('COMMERCE.SETTINGS.PICKER.DESCRIPTION')"
    :show-confirm-button="false"
    :cancel-button-label="t('COMMERCE.SETTINGS.FORM.CANCEL')"
    width="md"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-2">
      <button
        v-for="option in options"
        :key="option.provider"
        type="button"
        class="flex items-center gap-3 rounded-xl border border-solid border-n-weak bg-n-solid-1 p-3 text-start enabled:hover:border-n-strong disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="!option.available"
        :data-test-id="`commerce-provider-${option.provider}`"
        @click="emit('select', option.provider)"
      >
        <span
          class="grid size-10 shrink-0 place-items-center rounded-xl border border-n-strong bg-n-alpha-3"
        >
          <Icon :icon="option.icon" class="size-4" />
        </span>
        <span class="flex min-w-0 flex-col gap-0.5">
          <span class="flex flex-wrap items-center gap-2">
            <span class="text-heading-3 text-n-slate-12">
              {{ providerName(option.provider) }}
            </span>
            <Label
              v-if="!option.available"
              compact
              variant="subtle"
              tone="neutral"
              :label="t('COMMERCE.SETTINGS.PICKER.UNAVAILABLE')"
            />
          </span>
          <span class="text-body-main text-n-slate-11">
            {{ option.hint }}
          </span>
        </span>
      </button>
      <p v-if="hasUnavailable" class="text-label-small text-n-slate-11">
        {{ t('COMMERCE.SETTINGS.PICKER.UNAVAILABLE_NOTE') }}
      </p>
    </div>
  </Dialog>
</template>
