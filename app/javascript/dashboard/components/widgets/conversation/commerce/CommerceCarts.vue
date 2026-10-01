<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Button from 'dashboard/components-next/button/Button.vue';
import CommerceAPI from 'dashboard/api/commerce';
import { formatAmount, relativeTime } from './commerceHelper';
import { useCommerceLabels } from './useCommerceLabels';

// The conversation contact's abandoned carts (docs/commerce/30-abandoned-carts.md, 31-sales-recovery.md). Shown only
// when there are some. "Prepare recovery message" puts a message with the store's own link into the reply box: the agent
// reviews and sends it; Lynomia never sends it.
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  // Only this store's carts (the Store tab), or every store's (Overview).
  storeId: { type: Number, default: null },
  // Changing it reads the carts again (live updates, Refresh).
  reloadKey: { type: Number, default: 0 },
});

const { t, locale } = useI18n();
const { isAdmin } = useAdmin();
const { apiErrorMessage, providerName } = useCommerceLabels();

const views = ref([]);
const expanded = ref({});
const preparing = ref('');
const notices = ref({});

const matchLabel = match =>
  ({
    linked_customer: t('COMMERCE.CARTS.MATCH.LINKED_CUSTOMER'),
    verified_phone: t('COMMERCE.CARTS.MATCH.VERIFIED_PHONE'),
    verified_email: t('COMMERCE.CARTS.MATCH.VERIFIED_EMAIL'),
  })[match];

const carts = computed(() =>
  views.value
    .filter(view => !props.storeId || view.store.id === props.storeId)
    .flatMap(view => view.carts.map(cart => ({ ...cart, store: view.store })))
);
const failedStores = computed(() =>
  views.value.filter(
    view =>
      view.state === 'unavailable' &&
      view.error !== 'RECOVERY_DISABLED' &&
      (!props.storeId || view.store.id === props.storeId)
  )
);

const cartKey = cart => `${cart.store.id}-${cart.external_cart_id}`;
const itemCount = cart =>
  (cart.items || []).reduce((sum, item) => sum + Number(item.quantity || 0), 0);
const when = seconds =>
  relativeTime(new Date(seconds * 1000).toISOString(), locale.value);
const coolingDown = cart =>
  cart.recovery?.cooldown_until &&
  cart.recovery.cooldown_until * 1000 > Date.now();

const load = async () => {
  try {
    const response = await CommerceAPI.getCarts(props.conversationId);
    views.value = response.data.stores;
  } catch {
    views.value = [];
  }
};

// Written in the agent's language from the store's own figures; the first name only when the contact has one.
const recoveryMessage = data => {
  const values = {
    name: data.first_name,
    count: data.items_count,
    store: data.store.name,
    total: formatAmount(data.total, data.currency, locale.value),
    url: data.recovery_url,
  };
  return data.first_name
    ? t('COMMERCE.CARTS.TEMPLATE.WITH_NAME', values)
    : t('COMMERCE.CARTS.TEMPLATE.WITHOUT_NAME', values);
};

const prepare = async (cart, overrideCooldown = false) => {
  const key = cartKey(cart);
  preparing.value = key;
  notices.value = { ...notices.value, [key]: '' };
  try {
    const response = await CommerceAPI.prepareRecovery(
      props.conversationId,
      cart.store.id,
      cart.external_cart_id,
      { overrideCooldown }
    );
    emitter.emit(
      BUS_EVENTS.INSERT_INTO_RICH_EDITOR,
      recoveryMessage(response.data)
    );
    useAlert(t('COMMERCE.CARTS.PREPARED'));
    await load();
  } catch (error) {
    notices.value = { ...notices.value, [key]: apiErrorMessage(error) };
  } finally {
    preparing.value = '';
  }
};

watch(
  () => [props.conversationId, props.reloadKey],
  () => load(),
  { immediate: true }
);
</script>

<template>
  <div>
    <section
      v-if="carts.length || failedStores.length"
      class="flex flex-col gap-2"
      data-test-id="commerce-carts"
    >
      <span class="text-heading-3 text-n-slate-12">
        {{ t('COMMERCE.CARTS.TITLE') }}
      </span>
      <p
        v-for="view in failedStores"
        :key="view.store.id"
        class="text-label-small text-n-slate-11"
      >
        {{ t('COMMERCE.CARTS.UNAVAILABLE', { store: view.store.name }) }}
      </p>
      <div
        v-for="cart in carts"
        :key="cartKey(cart)"
        class="flex flex-col gap-1.5 rounded-lg border border-n-weak px-3 py-2"
        data-test-id="commerce-cart"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <span class="text-body-main text-n-slate-12">
            {{ formatAmount(cart.total, cart.currency, locale) }}
          </span>
          <span class="text-label-small text-n-slate-11">
            {{
              t(
                'COMMERCE.CARTS.ITEMS',
                { count: itemCount(cart) },
                itemCount(cart)
              )
            }}
          </span>
        </div>
        <span class="text-label-small text-n-slate-11">
          {{
            t('COMMERCE.CARTS.STORE_AND_AGE', {
              store: cart.store.name,
              provider: providerName(cart.store.provider),
              time: relativeTime(cart.updated_at || cart.created_at, locale),
            })
          }}
        </span>
        <span class="text-label-small text-n-slate-11">
          {{ matchLabel(cart.match) }}
        </span>
        <ul
          v-if="expanded[cartKey(cart)]"
          class="flex flex-col gap-0.5 text-body-main text-n-slate-12"
          data-test-id="commerce-cart-items"
        >
          <li v-for="(item, index) in cart.items" :key="index">
            {{
              t('COMMERCE.CARTS.ITEM_LINE', {
                quantity: item.quantity,
                name: item.name || t('COMMERCE.CARTS.ITEM'),
              })
            }}
          </li>
        </ul>
        <span
          v-if="cart.recovery?.sent_at"
          class="text-label-small text-n-teal-11"
          data-test-id="commerce-cart-sent"
        >
          {{ t('COMMERCE.CARTS.SENT', { time: when(cart.recovery.sent_at) }) }}
        </span>
        <span
          v-else-if="cart.recovery?.prepared_at"
          class="text-label-small text-n-slate-11"
        >
          {{
            t('COMMERCE.CARTS.PREPARED_AT', {
              time: when(cart.recovery.prepared_at),
            })
          }}
        </span>
        <span
          v-if="coolingDown(cart)"
          class="text-label-small text-n-amber-11"
          data-test-id="commerce-cart-cooldown"
        >
          {{
            t('COMMERCE.CARTS.COOLDOWN', {
              time: when(cart.recovery.cooldown_until),
            })
          }}
        </span>
        <p
          v-if="notices[cartKey(cart)]"
          class="text-label-small text-n-ruby-11"
          data-test-id="commerce-cart-notice"
        >
          {{ notices[cartKey(cart)] }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            :label="
              expanded[cartKey(cart)]
                ? t('COMMERCE.CARTS.HIDE')
                : t('COMMERCE.CARTS.VIEW')
            "
            variant="link"
            size="xs"
            @click="
              expanded = {
                ...expanded,
                [cartKey(cart)]: !expanded[cartKey(cart)],
              }
            "
          />
          <Button
            v-if="!coolingDown(cart)"
            :label="t('COMMERCE.CARTS.PREPARE')"
            variant="faded"
            size="xs"
            :is-loading="preparing === cartKey(cart)"
            data-test-id="commerce-cart-prepare"
            @click="prepare(cart)"
          />
          <Button
            v-else-if="isAdmin"
            :label="t('COMMERCE.CARTS.OVERRIDE')"
            variant="faded"
            color="slate"
            size="xs"
            :is-loading="preparing === cartKey(cart)"
            data-test-id="commerce-cart-override"
            @click="prepare(cart, true)"
          />
        </div>
      </div>
    </section>
  </div>
</template>
