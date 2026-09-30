<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CommerceAPI from 'dashboard/api/commerce';
import CommerceOrderItem from './CommerceOrderItem.vue';
import { relativeTime } from './commerceHelper';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const { t, locale } = useI18n();
const { isAdmin } = useAdmin();
const { run } = useAbortableRequest();

const stores = ref([]);
const storeId = ref(null);
const panel = ref(null);
const isLoading = ref(true);
const loadError = ref('');
const isSearchOpen = ref(false);
const query = ref('');
const candidates = ref(null);
const searchError = ref('');
const isSearching = ref(false);
const linkingToken = ref('');

const errorMessage = error => {
  const code = error?.response?.data?.error?.code;
  return code ? t(`COMMERCE.ERRORS.${code}`) : t('COMMERCE.ERRORS.GENERIC');
};

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
  return t(`COMMERCE.PANEL.MATCH_SOURCE.${link.match_source.toUpperCase()}`);
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

const loadPanel = async () => {
  if (!storeId.value) return;
  isLoading.value = true;
  loadError.value = '';
  resetSearch();
  try {
    const response = await run(signal =>
      CommerceAPI.getPanel(props.conversationId, storeId.value, { signal })
    );
    if (response) panel.value = response.data;
  } catch (error) {
    loadError.value = errorMessage(error);
  } finally {
    isLoading.value = false;
  }
};

const loadStores = async () => {
  isLoading.value = true;
  panel.value = null;
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
    if (storeId.value) await loadPanel();
  } catch (error) {
    loadError.value = errorMessage(error);
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
    searchError.value = errorMessage(error);
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
    searchError.value = errorMessage(error);
  } finally {
    linkingToken.value = '';
  }
};

const unlink = async () => {
  try {
    await CommerceAPI.unlinkCustomer(props.conversationId, storeId.value);
    await loadPanel();
  } catch (error) {
    loadError.value = errorMessage(error);
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
    <div v-if="isLoading && !panel" class="flex justify-center p-4">
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
            t(`COMMERCE.ERRORS.${panel.error}`)
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
            {{
              panel.state === 'not_found'
                ? t('COMMERCE.PANEL.NOT_FOUND')
                : t(`COMMERCE.PANEL.${panel.state.toUpperCase()}`)
            }}
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
              <span class="truncate text-label-small text-n-slate-11" dir="ltr">
                {{
                  [candidate.email, candidate.phone].filter(Boolean).join(' · ')
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
      </template>
    </template>
  </div>
</template>
