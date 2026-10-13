<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Skeleton from 'dashboard/components-next/skeleton/Skeleton.vue';
import DocsLink from 'dashboard/components-next/docs-link/DocsLink.vue';
import StatusChip from '../components/StatusChip.vue';
import ThreadMessage from '../components/ThreadMessage.vue';
import ThreadEvent from '../components/ThreadEvent.vue';
import ReplyBox from '../components/ReplyBox.vue';
import PlatformSupportAPI from '../platformSupportApi';
import { refreshPlatformSupportUnreadCount } from '../platformSupportStore';

// One ticket, in full.
//
// WHAT THIS PAGE NEVER CONTAINS, and the reason it cannot: internal notes (no tenant route and no serializer
// key exists for them), the operator's name (`author_name` is the literal "Lynomia Support" for every operator
// message), SLA targets or countdowns, the assignee, assignment or priority history, or `metadata`. None of
// that is a rule this component keeps -- the payload simply has none of it
// (docs/platform-support/12-refresh-against-product-refinement.md §2).
//
// The thread is public messages and customer-visible events in ONE chronological list, oldest first, because
// that is how the conversation actually happened.

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountId, accountScopedRoute } = useAccount();

const ticket = ref(null);
const messages = ref([]);
const events = ref([]);
const loadError = ref(null);
const isLoading = ref(true);
const isSending = ref(false);
const sendError = ref(null);
const replyBoxRef = ref(null);
// Whether Lynomia had replied since this customer last looked, captured BEFORE mark_viewed clears the flag --
// otherwise the indicator the customer came here for disappears before they can see it.
const arrivedUnread = ref(false);

const ticketId = computed(() => route.params.ticketId);

const isClosed = computed(() => ticket.value?.status === 'closed');
const isResolved = computed(() => ticket.value?.status === 'resolved');

const statusSentence = computed(() => {
  if (!ticket.value) return '';

  const key = `PLATFORM_SUPPORT.STATUS_SENTENCE.${ticket.value.status.toUpperCase()}`;
  const translated = t(key);

  // A status this build has no sentence for says nothing rather than saying the enum name at a customer.
  return translated === key ? '' : translated;
});

const loadErrorMessage = computed(() => {
  if (!loadError.value) return '';
  if (loadError.value.response?.status === 404) {
    return t('PLATFORM_SUPPORT.ERROR.NOT_FOUND');
  }

  return (
    loadError.value.response?.data?.message ||
    t('PLATFORM_SUPPORT.ERROR.DETAIL_FAILED')
  );
});

const sendErrorMessage = computed(() => {
  if (!sendError.value) return '';

  const data = sendError.value.response?.data;

  return (
    data?.message || data?.error || t('PLATFORM_SUPPORT.ERROR.REPLY_FAILED')
  );
});

// The ticket's `description` is NOT rendered here. Creating a ticket writes the customer's own words as the
// thread's first message as well (PlatformSupport::TicketCreation), which is what carries the opening
// attachments, so the thread already opens with it. Rendering the column too would show the same text twice.
// The column remains the canonical statement for the list and for search.

// Messages and events in one list. A message and an event stamped in the same second keep their relative
// order from the two payloads, which is the order the server wrote them in.
const thread = computed(() => {
  const entries = [
    ...messages.value.map(message => ({
      key: `message-${message.id}`,
      kind: 'message',
      at: Number(message.created_at) || 0,
      message,
    })),
    ...events.value.map(event => ({
      key: `event-${event.id}`,
      kind: 'event',
      at: Number(event.created_at) || 0,
      event,
    })),
  ];

  return entries.sort((a, b) => a.at - b.at);
});

const load = async () => {
  isLoading.value = true;
  loadError.value = null;

  try {
    const [ticketResponse, messagesResponse, eventsResponse] =
      await Promise.all([
        PlatformSupportAPI.getTicket(ticketId.value),
        PlatformSupportAPI.getMessages(ticketId.value),
        PlatformSupportAPI.getEvents(ticketId.value),
      ]);

    // All three endpoints answer in the `payload` envelope this module's serializers use, including the
    // single-ticket one (app/views/api/v1/accounts/platform_support/tickets/show.json.jbuilder).
    ticket.value = ticketResponse.data.payload;
    messages.value = messagesResponse.data.payload || [];
    events.value = eventsResponse.data.payload || [];
    arrivedUnread.value = Boolean(ticket.value.unread);
  } catch (requestError) {
    loadError.value = requestError;
  } finally {
    isLoading.value = false;
  }
};

// Stamps `customer_last_viewed_at`, which is what clears the dot on the card and the sidebar badge. Opening
// the ticket IS the act of reading it, so this is not a button.
const markViewed = async () => {
  try {
    await PlatformSupportAPI.markViewed(ticketId.value);
    await refreshPlatformSupportUnreadCount(accountId.value);
  } catch {
    // Deliberately silent: failing to clear a dot must not interrupt reading the ticket.
  }
};

const send = async reply => {
  isSending.value = true;
  sendError.value = null;

  try {
    await PlatformSupportAPI.createMessage(ticketId.value, reply);
    replyBoxRef.value?.reset();
    // Refetched rather than appended: a reply to a RESOLVED ticket reopens it server side, so the status and
    // the event list both change and this page must not keep showing the state it had.
    await load();
    await markViewed();
  } catch (requestError) {
    sendError.value = requestError;
  } finally {
    isSending.value = false;
  }
};

const openNewTicket = () =>
  router.push(
    accountScopedRoute(
      'platform_support_tickets_new',
      {},
      { category: ticket.value?.category }
    )
  );

onMounted(async () => {
  await load();
  if (!loadError.value) await markViewed();
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1">
    <div class="flex flex-col w-full max-w-3xl gap-6 px-4 py-6 mx-auto sm:px-6">
      <Button
        variant="link"
        color="slate"
        size="sm"
        justify="start"
        class="w-fit"
        icon="i-lucide-arrow-left"
        :label="t('PLATFORM_SUPPORT.DETAIL.BACK_TO_LIST')"
        @click="
          router.push(accountScopedRoute('platform_support_tickets_index'))
        "
      />

      <div v-if="isLoading" class="flex flex-col gap-4" :aria-busy="true">
        <Skeleton width="w-32" height="h-3" />
        <Skeleton width="w-2/3" height="h-6" />
        <Skeleton width="w-full" height="h-20" shape="block" />
        <Skeleton width="w-full" height="h-20" shape="block" />
      </div>

      <Banner v-else-if="loadErrorMessage" color="ruby">
        {{ loadErrorMessage }}
      </Banner>

      <template v-else-if="ticket">
        <header class="flex flex-col gap-3">
          <div class="flex flex-wrap items-center gap-2">
            <span class="tabular-nums text-label-small text-n-slate-10">
              {{ ticket.reference }}
            </span>
            <span
              v-if="arrivedUnread"
              data-test-id="platform-support-detail-unread"
              class="inline-flex items-center gap-1.5 text-label-small text-n-brand"
            >
              <span class="size-2 rounded-full bg-n-brand" />
              {{ t('PLATFORM_SUPPORT.DETAIL.NEW_REPLY') }}
            </span>
          </div>

          <h1 class="m-0 break-words text-heading-1 text-n-slate-12">
            {{ ticket.subject }}
          </h1>

          <div class="flex flex-wrap items-center gap-1.5">
            <StatusChip kind="status" :value="ticket.status" />
            <StatusChip kind="category" :value="ticket.category" />
            <StatusChip kind="priority" :value="ticket.priority" />
            <span class="text-label-small text-n-slate-10">
              {{
                t('PLATFORM_SUPPORT.DETAIL.OPENED_ON', {
                  date: messageTimestamp(ticket.created_at, 'MMM d, yyyy'),
                })
              }}
            </span>
          </div>

          <p v-if="statusSentence" class="m-0 text-body-main text-n-slate-11">
            {{ statusSentence }}
          </p>
        </header>

        <section class="flex flex-col gap-4">
          <h2 class="sr-only">{{ t('PLATFORM_SUPPORT.THREAD.TITLE') }}</h2>
          <ul class="flex flex-col gap-4 p-0 m-0 list-none">
            <template v-for="entry in thread" :key="entry.key">
              <ThreadMessage
                v-if="entry.kind === 'message'"
                :message="entry.message"
              />
              <ThreadEvent v-else :event="entry.event" />
            </template>
          </ul>
        </section>

        <ReplyBox
          v-if="!isClosed"
          ref="replyBoxRef"
          :reopens="isResolved"
          :is-submitting="isSending"
          :error-message="sendErrorMessage"
          @send="send"
        />

        <section v-else class="flex flex-col gap-3 pt-4 border-t border-n-weak">
          <p class="m-0 text-body-main text-n-slate-11">
            {{ t('PLATFORM_SUPPORT.DETAIL.CLOSED_HINT') }}
          </p>
          <Button
            variant="faded"
            color="slate"
            size="sm"
            class="w-fit"
            icon="i-lucide-plus"
            :label="t('PLATFORM_SUPPORT.DETAIL.OPEN_NEW_TICKET')"
            @click="openNewTicket"
          />
        </section>

        <DocsLink
          article-key="contactLynomiaSupport"
          :label="t('PLATFORM_SUPPORT.DOCS.WHAT_STATUSES_MEAN')"
        />
      </template>
    </div>
  </section>
</template>
