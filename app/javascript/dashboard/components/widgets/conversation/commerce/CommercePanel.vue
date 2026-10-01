<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CommerceAPI from 'dashboard/api/commerce';
import CommerceOrderItem from './CommerceOrderItem.vue';
import CommerceOverview from './CommerceOverview.vue';
import CommerceOrderSearch from './CommerceOrderSearch.vue';
import { relativeTime } from './commerceHelper';
import { useCommerceLabels } from './useCommerceLabels';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  // The conversation's contact: live updates (commerce.customer.updated) for this contact refresh the open view.
  contactId: { type: [Number, String], default: null },
});

const { t, locale } = useI18n();
const { errorMessage, apiErrorMessage, matchSource, matchState } =
  useCommerceLabels();
const { isAdmin } = useAdmin();
const { run } = useAbortableRequest();

// Two views: Customer 360 across the stores, and one store's own view (link, search, its orders). The overview is
// offered when the account has several stores and opens first for a contact linked in several of them; an agent's own
// choice is remembered in this browser.
const VIEW_STORAGE_KEY = 'lynomia.commerce.view';
const VIEWS = { OVERVIEW: 'overview', STORE: 'store' };
const savedView = () => {
  try {
    return Object.values(VIEWS).find(
      value => value === window.localStorage.getItem(VIEW_STORAGE_KEY)
    );
  } catch {
    return undefined;
  }
};
const saveView = value => {
  try {
    window.localStorage.setItem(VIEW_STORAGE_KEY, value);
  } catch {
    // The choice is a convenience; the panel works without it.
  }
};

const stores = ref([]);
const storeId = ref(null);
const view = ref(VIEWS.STORE);
const overview = ref(null);
const panel = ref(null);
const isLoading = ref(true);
const loadError = ref('');
const isSearchOpen = ref(false);
const query = ref('');
const candidates = ref(null);
const searchError = ref('');
const isSearching = ref(false);
const linkingToken = ref('');

const hasOverview = computed(() => stores.value.length > 1);
const isOverview = computed(
  () => hasOverview.value && view.value === VIEWS.OVERVIEW
);

const storeOptions = computed(() =>
  stores.value.map(store => ({ value: store.id, label: store.name }))
);

const shownCandidates = computed(
  () => candidates.value ?? panel.value?.candidates ?? []
);

const matchLabel = computed(() => {
  const link = panel.value?.link;
  if (!link) return '';
  if (link.match_source === 'manual' && link.confirmed_by?.name) {
    return t('COMMERCE.PANEL.MATCH_SOURCE.MANUAL_BY', {
      name: link.confirmed_by.name,
    });
  }
  return matchSource(link.match_source);
});

const linkedName = computed(
  () => panel.value?.orders?.find(order => order.customer?.name)?.customer.name
);

const lastUpdated = computed(() =>
  panel.value?.fetched_at
    ? t('COMMERCE.PANEL.LAST_UPDATED', {
        time: relativeTime(panel.value.fetched_at, locale.value),
      })
    : ''
);

const resetSearch = () => {
  isSearchOpen.value = false;
  query.value = '';
  candidates.value = null;
  searchError.value = '';
};

// `silent`: a live update or reconnect refetches the open view without closing the agent's search or showing a spinner.
const loadPanel = async ({ silent = false } = {}) => {
  if (!storeId.value) return;
  isLoading.value = !silent;
  if (!silent) {
    loadError.value = '';
    resetSearch();
  }
  try {
    const response = await run(signal =>
      CommerceAPI.getPanel(props.conversationId, storeId.value, { signal })
    );
    if (response) panel.value = response.data;
  } catch (error) {
    loadError.value = apiErrorMessage(error);
  } finally {
    isLoading.value = false;
  }
};

const loadOverview = async ({ silent = false } = {}) => {
  isLoading.value = !silent;
  if (!silent) loadError.value = '';
  try {
    const response = await run(signal =>
      CommerceAPI.getOverview(props.conversationId, { signal })
    );
    if (response) overview.value = response.data;
  } catch (error) {
    loadError.value = apiErrorMessage(error);
  } finally {
    isLoading.value = false;
  }
};

const loadView = options =>
  isOverview.value ? loadOverview(options) : loadPanel(options);

// Live updates: the backend sends only ids. Several events in a burst (one per store) make one refetch.
const LIVE_UPDATE_DEBOUNCE_MS = 500;
const DEFAULT_REFRESH_COOLDOWN_SECONDS = 30;
let liveUpdateTimer = null;
const onCustomerUpdated = data => {
  if (!props.contactId || Number(data?.contact_id) !== Number(props.contactId))
    return;
  if (!isOverview.value && Number(data.store_id) !== Number(storeId.value))
    return;
  clearTimeout(liveUpdateTimer);
  liveUpdateTimer = setTimeout(
    () => loadView({ silent: true }),
    LIVE_UPDATE_DEBOUNCE_MS
  );
};
useEmitter(BUS_EVENTS.COMMERCE_CUSTOMER_UPDATED, onCustomerUpdated);
// Events sent while the socket was down are not replayed, so the open view is read again on reconnect.
useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT, () => {
  if (stores.value.length) loadView({ silent: true });
});
onBeforeUnmount(() => clearTimeout(liveUpdateTimer));

const isRefreshing = ref(false);
const refreshNotice = ref('');
const refresh = async () => {
  isRefreshing.value = true;
  refreshNotice.value = '';
  try {
    const response = await CommerceAPI.refresh(
      props.conversationId,
      isOverview.value ? null : storeId.value
    );
    if (isOverview.value) overview.value = response.data;
    else panel.value = response.data;
  } catch (error) {
    if (error?.response?.status === 429) {
      refreshNotice.value = t('COMMERCE.PANEL.REFRESH_COOLDOWN', {
        seconds:
          error.response.data?.error?.retry_after ??
          DEFAULT_REFRESH_COOLDOWN_SECONDS,
      });
    } else {
      loadError.value = apiErrorMessage(error);
    }
  } finally {
    isRefreshing.value = false;
  }
};

const setView = value => {
  view.value = value;
  saveView(value);
  loadView();
};

const openStore = id => {
  storeId.value = id;
  setView(VIEWS.STORE);
};

const loadStores = async () => {
  isLoading.value = true;
  panel.value = null;
  overview.value = null;
  loadError.value = '';
  try {
    const response = await run(signal =>
      CommerceAPI.getConversationStores(props.conversationId, { signal })
    );
    if (!response) return;
    stores.value = response.data.payload;
    const preferred =
      stores.value.find(store => store.linked) || stores.value[0];
    storeId.value = preferred?.id ?? null;
    const linkedCount = stores.value.filter(store => store.linked).length;
    view.value =
      savedView() || (linkedCount > 1 ? VIEWS.OVERVIEW : VIEWS.STORE);
    if (storeId.value) await loadView();
  } catch (error) {
    loadError.value = apiErrorMessage(error);
  } finally {
    isLoading.value = false;
  }
};

const search = async () => {
  isSearching.value = true;
  searchError.value = '';
  try {
    const response = await CommerceAPI.searchCustomers(
      props.conversationId,
      storeId.value,
      query.value
    );
    candidates.value = response.data.candidates;
  } catch (error) {
    searchError.value = apiErrorMessage(error);
  } finally {
    isSearching.value = false;
  }
};

const link = async candidate => {
  linkingToken.value = candidate.token;
  try {
    const response = await CommerceAPI.linkCustomer(
      props.conversationId,
      storeId.value,
      candidate.token
    );
    panel.value = response.data;
    resetSearch();
  } catch (error) {
    searchError.value = apiErrorMessage(error);
  } finally {
    linkingToken.value = '';
  }
};

const unlink = async () => {
  try {
    await CommerceAPI.unlinkCustomer(props.conversationId, storeId.value);
    await loadPanel();
  } catch (error) {
    loadError.value = apiErrorMessage(error);
  }
};

const onStoreChange = value => {
  storeId.value = Number(value);
  loadPanel();
};

watch(() => props.conversationId, loadStores, { immediate: true });
</script>

<template>
  <div
    class="flex flex-col gap-3 px-4 py-2 text-n-slate-12"
    data-test-id="commerce-panel"
  >
    <div
      v-if="isLoading && !panel && !overview"
      class="flex justify-center p-4"
    >
      <Spinner class="text-n-brand" />
    </div>

    <div
      v-else-if="!stores.length"
      class="flex flex-col gap-1 text-body-main text-n-slate-11"
    >
      <span>{{ t('COMMERCE.PANEL.NO_STORES') }}</span>
      <span v-if="isAdmin">{{ t('COMMERCE.PANEL.NO_STORES_ADMIN') }}</span>
    </div>

    <template v-else>
      <div class="flex items-center gap-1">
        <div
          v-if="hasOverview"
          class="flex gap-1"
          role="tablist"
          data-test-id="commerce-views"
        >
          <Button
            :label="t('COMMERCE.OVERVIEW.TAB')"
            :variant="isOverview ? 'faded' : 'ghost'"
            color="slate"
            size="xs"
            role="tab"
            :aria-selected="isOverview"
            data-test-id="commerce-view-overview"
            @click="setView(VIEWS.OVERVIEW)"
          />
          <Button
            :label="t('COMMERCE.OVERVIEW.STORE_TAB')"
            :variant="isOverview ? 'ghost' : 'faded'"
            color="slate"
            size="xs"
            role="tab"
            :aria-selected="!isOverview"
            data-test-id="commerce-view-store"
            @click="setView(VIEWS.STORE)"
          />
        </div>
        <Button
          :label="t('COMMERCE.PANEL.REFRESH')"
          icon="i-lucide-refresh-cw"
          variant="ghost"
          color="slate"
          size="xs"
          class="ms-auto"
          :is-loading="isRefreshing"
          data-test-id="commerce-refresh"
          @click="refresh"
        />
      </div>
      <p
        v-if="refreshNotice"
        class="text-label-small text-n-slate-11"
        data-test-id="commerce-refresh-notice"
      >
        {{ refreshNotice }}
      </p>

      <template v-if="isOverview">
        <p v-if="loadError" class="text-body-main text-n-ruby-11">
          {{ loadError }}
        </p>
        <CommerceOverview
          v-if="overview"
          :overview="overview"
          @open-store="openStore"
        />
        <CommerceOrderSearch
          v-if="overview"
          :conversation-id="conversationId"
        />
      </template>

      <template v-else>
        <label
          v-if="stores.length > 1"
          class="flex flex-col gap-1 text-label-small text-n-slate-11"
        >
          {{ t('COMMERCE.PANEL.STORE') }}
          <Select
            :model-value="storeId"
            class="!w-full [&>select]:w-full"
            :options="storeOptions"
            @update:model-value="onStoreChange"
          />
        </label>

        <p v-if="loadError" class="text-body-main text-n-ruby-11">
          {{ loadError }}
        </p>

        <template v-if="panel">
          <p
            v-if="panel.error"
            class="flex flex-col gap-0.5 rounded-lg bg-n-amber-2 px-3 py-2 text-body-main text-n-amber-11"
            data-test-id="commerce-stale"
          >
            <span>{{ t('COMMERCE.PANEL.UPDATE_FAILED') }}</span>
            <span v-if="panel.stale && lastUpdated">{{ lastUpdated }}</span>
            <span v-else-if="!panel.stale">{{
              errorMessage(panel.error)
            }}</span>
          </p>

          <template v-if="panel.state === 'linked'">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div class="flex flex-col">
                <span class="text-label-small text-n-slate-11">
                  {{ t('COMMERCE.PANEL.LINKED_CUSTOMER') }}
                </span>
                <span v-if="linkedName" class="text-heading-3">{{
                  linkedName
                }}</span>
                <span class="text-label-small text-n-slate-11">{{
                  matchLabel
                }}</span>
              </div>
              <div class="flex gap-1">
                <Button
                  :label="t('COMMERCE.PANEL.CHANGE')"
                  variant="ghost"
                  color="slate"
                  size="xs"
                  @click="isSearchOpen = !isSearchOpen"
                />
                <Button
                  :label="t('COMMERCE.PANEL.UNLINK')"
                  variant="ghost"
                  color="ruby"
                  size="xs"
                  @click="unlink"
                />
              </div>
            </div>
            <div v-if="panel.orders">
              <p
                v-if="!panel.orders.length"
                class="text-body-main text-n-slate-11"
              >
                {{ t('COMMERCE.PANEL.NO_ORDERS') }}
              </p>
              <CommerceOrderItem
                v-for="order in panel.orders"
                :key="order.external_order_id"
                :order="order"
              />
            </div>
          </template>

          <template v-else-if="panel.state !== 'unavailable'">
            <p
              class="text-body-main text-n-slate-11"
              data-test-id="commerce-match-state"
            >
              {{ matchState(panel.state) }}
            </p>
            <Button
              v-if="!isSearchOpen"
              :label="t('COMMERCE.PANEL.LINK_CUSTOMER')"
              variant="faded"
              size="sm"
              @click="isSearchOpen = true"
            />
          </template>

          <div v-if="isSearchOpen" class="flex flex-col gap-2">
            <div class="flex gap-2">
              <Input
                v-model="query"
                class="flex-1"
                size="sm"
                :placeholder="t('COMMERCE.PANEL.SEARCH_PLACEHOLDER')"
                @enter="search"
              />
              <Button
                :label="t('COMMERCE.PANEL.SEARCH')"
                size="sm"
                :is-loading="isSearching"
                :disabled="!query.trim()"
                @click="search"
              />
            </div>
            <span class="text-label-small text-n-slate-11">{{
              t('COMMERCE.PANEL.SEARCH_HINT')
            }}</span>
            <p v-if="searchError" class="text-body-main text-n-ruby-11">
              {{ searchError }}
            </p>
            <p
              v-else-if="candidates && !candidates.length"
              class="text-body-main text-n-slate-11"
            >
              {{ t('COMMERCE.PANEL.NO_RESULTS') }}
            </p>
          </div>

          <ul
            v-if="panel.state !== 'linked' || candidates"
            class="flex flex-col gap-2"
            data-test-id="commerce-candidates"
          >
            <li
              v-for="candidate in shownCandidates"
              :key="candidate.token"
              class="flex items-center justify-between gap-2 rounded-lg border border-n-weak px-3 py-2"
            >
              <div class="flex min-w-0 flex-col">
                <span class="truncate text-body-main text-n-slate-12">{{
                  candidate.name
                }}</span>
                <span
                  class="truncate text-label-small text-n-slate-11"
                  dir="ltr"
                >
                  {{
                    [candidate.email, candidate.phone]
                      .filter(Boolean)
                      .join(' · ')
                  }}
                </span>
                <span class="text-label-small text-n-slate-11">
                  {{
                    candidate.registered
                      ? t('COMMERCE.PANEL.REGISTERED')
                      : t('COMMERCE.PANEL.GUEST')
                  }}
                </span>
              </div>
              <Button
                :label="t('COMMERCE.PANEL.LINK')"
                size="xs"
                :is-loading="linkingToken === candidate.token"
                @click="link(candidate)"
              />
            </li>
          </ul>

          <CommerceOrderSearch
            :key="storeId"
            :conversation-id="conversationId"
            :store-id="storeId"
          />
        </template>
      </template>
    </template>
  </div>
</template>
