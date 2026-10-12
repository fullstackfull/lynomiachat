<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import DocsLink from 'dashboard/components-next/docs-link/DocsLink.vue';
import NewTicketForm from '../components/NewTicketForm.vue';
import PlatformSupportAPI from '../platformSupportApi';

// The create page.
//
// ON SUCCESS THE CUSTOMER LANDS ON THE TICKET, not on a toast. The reference is the receipt, and the detail
// page is where the sentence about what happens next belongs (docs/platform-support/04-customer-ux.md §3.2).

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const isSubmitting = ref(false);
const error = ref(null);

// A 422 carries the reason, which is the message the customer needs; anything else is unexpected and gets the
// generic sentence rather than a stack of server internals.
const errorMessage = computed(() => {
  if (!error.value) return '';

  const data = error.value.response?.data;

  return (
    data?.message || data?.error || t('PLATFORM_SUPPORT.ERROR.CREATE_FAILED')
  );
});

const toList = () =>
  router.push(accountScopedRoute('platform_support_tickets_index'));

const submit = async ticket => {
  isSubmitting.value = true;
  error.value = null;

  try {
    const response = await PlatformSupportAPI.createTicket(ticket);
    router.push(
      accountScopedRoute('platform_support_tickets_show', {
        ticketId: response.data.id,
      })
    );
  } catch (requestError) {
    error.value = requestError;
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1">
    <div class="flex flex-col w-full max-w-2xl gap-6 px-4 py-6 mx-auto sm:px-6">
      <header class="flex flex-col gap-2">
        <Button
          variant="link"
          color="slate"
          size="sm"
          justify="start"
          class="w-fit"
          icon="i-lucide-arrow-left"
          :label="t('PLATFORM_SUPPORT.FORM.BACK_TO_LIST')"
          @click="toList"
        />
        <h1 class="m-0 text-heading-1 text-n-slate-12">
          {{ t('PLATFORM_SUPPORT.FORM.HEADER') }}
        </h1>
        <p class="m-0 text-body-main text-n-slate-11">
          {{ t('PLATFORM_SUPPORT.FORM.DESCRIPTION') }}
        </p>
        <DocsLink
          article-key="contactLynomiaSupport"
          :label="t('PLATFORM_SUPPORT.DOCS.WHAT_TO_INCLUDE')"
        />
      </header>

      <NewTicketForm
        :is-submitting="isSubmitting"
        :error-message="errorMessage"
        :initial-category="route.query.category || ''"
        @submit="submit"
        @cancel="toList"
      />
    </div>
  </section>
</template>
