<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';

import BillingSubscriptionAPI from 'dashboard/api/billingSubscription';
import PendingPlanAPI from 'dashboard/api/pendingPlan';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import BillingCard from '../billing/components/BillingCard.vue';
import DetailItem from '../billing/components/DetailItem.vue';
import ButtonV4 from 'next/button/Button.vue';

// ---------- texts (Arabic / English, by the user's Chatwoot language) ----------
const TEXT = {
  en: {
    TITLE: 'Subscription',
    DESCRIPTION: 'Manage your plan, payment and usage.',
    LOADING: 'Loading subscription…',
    LOAD_ERROR: 'Could not load subscription details.',
    CURRENT: 'Current subscription',
    PLAN: 'Plan',
    STATUS: 'Status',
    NO_PLAN: '—',
    MANAGE_BILLING: 'Manage billing',
    MANAGE_BILLING_DESC: 'Update your card, download invoices or cancel.',
    STATUS_TRIAL: 'Free trial',
    STATUS_TRIAL_ENDED: 'Trial ended',
    STATUS_ACTIVE: 'Active',
    STATUS_ACTIVE_CANCELING: 'Active (cancels at period end)',
    STATUS_PAST_DUE: 'Payment failed',
    STATUS_PAST_DUE_LOCKED: 'Payment failed — locked',
    STATUS_CANCELED: 'Canceled',
    STATUS_NONE: 'No subscription',
    STATUS_MANUAL: 'Active (managed by administrator)',
    DATE_TRIAL: 'Trial ends on',
    DATE_RENEWS: 'Renews on',
    DATE_ENDS: 'Ends on',
    DATE_GRACE: 'Pay before',
    USAGE: 'Usage',
    USAGE_DESC: 'Your usage compared to the limits that apply to this account.',
    AGENTS: 'Agents',
    INBOXES: 'Inboxes',
    STORES: 'Commerce stores',
    UNLIMITED: 'Unlimited',
    PLANS: 'Plans',
    PLANS_DESC: 'Choose the plan that fits your team.',
    NO_PLANS: 'No plans are available yet.',
    PER_MONTH: '/ month',
    PER_YEAR: '/ year',
    PER_AGENT: 'per agent',
    SUBSCRIBE: 'Subscribe',
    CURRENT_PLAN: 'Current plan',
    CHANGE_PLAN: 'Change plan',
    ADMIN_ONLY: 'Only account administrators can manage the subscription.',
    CHECKOUT_SUCCESS:
      'Payment received. Your subscription will be active in a few seconds.',
    CHECKOUT_CANCELED: 'Checkout was canceled. No payment was made.',
    RESUME_TITLE: 'Continue with {plan}',
    RESUME_BODY:
      'You chose this plan on our pricing page. Review it below and subscribe when you are ready — nothing has been charged.',
    RESUME_WORKSPACE: 'Paying as {account}.',
    RESUME_CHOOSE: 'Subscribe from a different workspace:',
    ACTION_ERROR: 'Something went wrong, please try again.',
    CONFIRM_TITLE: 'Change plan to {plan}?',
    CONFIRM_CHARGE:
      'Your plan will change to {plan} immediately. You will be charged {amount} now for the remaining days of this billing period.',
    CONFIRM_CREDIT:
      'Your plan will change to {plan} immediately. {amount} will be added as credit to your next invoices.',
    CONFIRM_FREE:
      'Your plan will change to {plan} immediately. Nothing will be charged now.',
    CONFIRM_BUTTON: 'Confirm change',
    CANCEL_BUTTON: 'Cancel',
    CHANGE_SUCCESS: 'Your plan was changed to {plan}.',
  },
  ar: {
    TITLE: 'الاشتراك',
    DESCRIPTION: 'إدارة خطتك والدفع والاستهلاك.',
    LOADING: 'جاري تحميل الاشتراك…',
    LOAD_ERROR: 'تعذّر تحميل تفاصيل الاشتراك.',
    CURRENT: 'الاشتراك الحالي',
    PLAN: 'الخطة',
    STATUS: 'الحالة',
    NO_PLAN: '—',
    MANAGE_BILLING: 'إدارة الفوترة',
    MANAGE_BILLING_DESC: 'تحديث البطاقة، تنزيل الفواتير أو إلغاء الاشتراك.',
    STATUS_TRIAL: 'تجربة مجانية',
    STATUS_TRIAL_ENDED: 'انتهت التجربة',
    STATUS_ACTIVE: 'فعّال',
    STATUS_ACTIVE_CANCELING: 'فعّال (يُلغى بنهاية الفترة)',
    STATUS_PAST_DUE: 'فشل الدفع',
    STATUS_PAST_DUE_LOCKED: 'فشل الدفع — الحساب مقفل',
    STATUS_CANCELED: 'ملغي',
    STATUS_NONE: 'لا يوجد اشتراك',
    STATUS_MANUAL: 'فعّال (بإدارة المسؤول)',
    DATE_TRIAL: 'تنتهي التجربة في',
    DATE_RENEWS: 'يتجدد في',
    DATE_ENDS: 'ينتهي في',
    DATE_GRACE: 'ادفع قبل',
    USAGE: 'الاستهلاك',
    USAGE_DESC: 'استهلاكك مقارنة بالحدود المطبَّقة على هذا الحساب.',
    AGENTS: 'الوكلاء',
    INBOXES: 'صناديق الوارد',
    STORES: 'متاجر Commerce',
    UNLIMITED: 'غير محدود',
    PLANS: 'الخطط',
    PLANS_DESC: 'اختر الخطة المناسبة لفريقك.',
    NO_PLANS: 'لا توجد خطط متاحة حالياً.',
    PER_MONTH: '/ شهرياً',
    PER_YEAR: '/ سنوياً',
    PER_AGENT: 'لكل وكيل',
    SUBSCRIBE: 'اشترك',
    CURRENT_PLAN: 'خطتك الحالية',
    CHANGE_PLAN: 'تغيير الخطة',
    ADMIN_ONLY: 'فقط مسؤولو الحساب يمكنهم إدارة الاشتراك.',
    CHECKOUT_SUCCESS: 'تم استلام الدفع. سيتفعّل اشتراكك خلال ثوانٍ.',
    CHECKOUT_CANCELED: 'تم إلغاء عملية الدفع. لم يتم خصم أي مبلغ.',
    RESUME_TITLE: 'أكمل الاشتراك في {plan}',
    RESUME_BODY:
      'اخترت هذه الباقة من صفحة الأسعار. راجعها بالأسفل واشترك متى كنت جاهزاً — لم يُخصم أي مبلغ بعد.',
    RESUME_WORKSPACE: 'الدفع باسم {account}.',
    RESUME_CHOOSE: 'اشترك من مساحة عمل أخرى:',
    ACTION_ERROR: 'حدث خطأ، حاول مرة أخرى.',
    CONFIRM_TITLE: 'تغيير الخطة إلى {plan}؟',
    CONFIRM_CHARGE:
      'ستتحوّل خطتك إلى {plan} فوراً، وسيتم خصم {amount} الآن مقابل الأيام المتبقية من الفترة الحالية.',
    CONFIRM_CREDIT:
      'ستتحوّل خطتك إلى {plan} فوراً، وسيُضاف {amount} كرصيد يُخصم من فواتيرك القادمة.',
    CONFIRM_FREE: 'ستتحوّل خطتك إلى {plan} فوراً، ولن يتم خصم أي مبلغ الآن.',
    CONFIRM_BUTTON: 'تأكيد التغيير',
    CANCEL_BUTTON: 'إلغاء',
    CHANGE_SUCCESS: 'تم تغيير خطتك إلى {plan}.',
  },
};

const { locale } = useI18n();
const lang = computed(() =>
  String(locale.value).startsWith('ar') ? 'ar' : 'en'
);
const t = (key, params = {}) => {
  const text = TEXT[lang.value][key] || TEXT.en[key] || key;
  return Object.entries(params).reduce(
    (result, [name, value]) => result.replace(`{${name}}`, value),
    text
  );
};

// ---------- state ----------
const route = useRoute();
const billing = ref(null);
const isLoading = ref(true);
const loadError = ref('');
const actionError = ref('');
const successMessage = ref('');
const busyPlanId = ref(null);
const isOpeningPortal = ref(false);
const pendingChange = ref(null); // { plan, preview }
const isChangingPlan = ref(false);

const checkoutResult = computed(() => route.query.checkout);

const subscription = computed(() => billing.value?.subscription || null);
const plans = computed(() => billing.value?.plans || []);

// THE PLAN A VISITOR PICKED ON THE PUBLIC PRICING PAGE, if they arrived here by that route.
//
// It reaches this page as `?plan=` put there by the resume redirect, NOT by the browser: the id was held
// server-side in the Rails session from the moment it was clicked, and was validated there before this
// page was ever named. The query parameter is a hint for the UI -- it decides which card to point at, and
// nothing else. Every write below still goes through the authorized endpoints, which re-read the plan.
const resumePlanId = computed(() => Number(route.query.plan) || null);
const resumePlan = computed(
  () => plans.value.find(plan => plan.id === resumePlanId.value) || null
);
// Other workspaces this person administers, offered only when there is more than one -- paying from the
// wrong workspace is an expensive mistake to make by accident.
const resumeAccounts = ref([]);
const otherResumeAccounts = computed(() =>
  resumeAccounts.value.filter(
    account => account.id !== Number(route.params.accountId)
  )
);

const isAdmin = computed(() => !!billing.value?.is_admin);
// { agents: { used, limit }, inboxes: {...}, stores: {...} } -- the count and the ceiling the server
// actually enforces, including any override the operator granted this account.
const usage = computed(() => billing.value?.usage || {});

// Commerce stores matter once the plan includes Lynomia Commerce, or the account still has stores connected.
const showsStores = computed(
  () => !!subscription.value?.plan_commerce || usage.value.stores?.used > 0
);

const hasPaidSubscription = computed(() => {
  const sub = subscription.value;
  return (
    !!sub &&
    sub.source === 'stripe' &&
    ['active', 'past_due'].includes(sub.status)
  );
});

// Plan changes are only possible on an active (not past due) Stripe subscription
const canChangePlan = computed(
  () =>
    subscription.value?.source === 'stripe' &&
    subscription.value?.status === 'active'
);

const isManual = computed(
  () =>
    subscription.value?.source === 'manual' &&
    subscription.value?.status === 'active'
);

// ---------- helpers ----------
const formatDate = value =>
  value ? format(new Date(value), 'dd MMM, yyyy') : '';

const formatMoney = (amount, currency) => {
  try {
    return new Intl.NumberFormat(lang.value === 'ar' ? 'ar' : 'en', {
      style: 'currency',
      currency: String(currency).toUpperCase(),
    }).format(amount);
  } catch {
    return `${amount} ${String(currency).toUpperCase()}`;
  }
};

const formatPrice = plan => formatMoney(plan.price, plan.currency);

const limitText = value =>
  value === undefined || value === null ? t('UNLIMITED') : value;

// "3 / 5", or "3 / Unlimited" when there is no ceiling. Never "3 / -1".
const usageText = entry => `${entry?.used ?? 0} / ${limitText(entry?.limit)}`;

const confirmMessage = computed(() => {
  if (!pendingChange.value) return '';
  const { plan, preview } = pendingChange.value;
  const amount = formatMoney(Math.abs(preview.amount), preview.currency);
  if (preview.amount > 0)
    return t('CONFIRM_CHARGE', { plan: plan.name, amount });
  if (preview.amount < 0)
    return t('CONFIRM_CREDIT', { plan: plan.name, amount });
  return t('CONFIRM_FREE', { plan: plan.name });
});

const statusInfo = computed(() => {
  const sub = subscription.value;
  if (!sub) return { label: t('STATUS_NONE'), dateLabel: '', date: '' };
  if (isManual.value) {
    return {
      label: t('STATUS_MANUAL'),
      dateLabel: t('DATE_ENDS'),
      date: formatDate(sub.current_period_end),
    };
  }

  switch (sub.status) {
    case 'trialing':
      return sub.usable
        ? {
            label: t('STATUS_TRIAL'),
            dateLabel: t('DATE_TRIAL'),
            date: formatDate(sub.trial_ends_at),
          }
        : { label: t('STATUS_TRIAL_ENDED'), dateLabel: '', date: '' };
    case 'active':
      return sub.cancel_at_period_end
        ? {
            label: t('STATUS_ACTIVE_CANCELING'),
            dateLabel: t('DATE_ENDS'),
            date: formatDate(sub.current_period_end),
          }
        : {
            label: t('STATUS_ACTIVE'),
            dateLabel: t('DATE_RENEWS'),
            date: formatDate(sub.current_period_end),
          };
    case 'past_due':
      return sub.usable
        ? {
            label: t('STATUS_PAST_DUE'),
            dateLabel: t('DATE_GRACE'),
            date: formatDate(sub.grace_period_ends_at),
          }
        : { label: t('STATUS_PAST_DUE_LOCKED'), dateLabel: '', date: '' };
    case 'canceled':
      return { label: t('STATUS_CANCELED'), dateLabel: '', date: '' };
    default:
      return { label: t('STATUS_NONE'), dateLabel: '', date: '' };
  }
});

// ---------- actions ----------
const errorText = error => error?.response?.data?.error || t('ACTION_ERROR');

const fetchBilling = async () => {
  try {
    const { data } = await BillingSubscriptionAPI.show();
    billing.value = data;
    loadError.value = '';
  } catch (error) {
    loadError.value = error?.response?.data?.error || t('LOAD_ERROR');
  } finally {
    isLoading.value = false;
  }
};

const subscribe = async plan => {
  actionError.value = '';
  busyPlanId.value = plan.id;
  try {
    const { data } = await BillingSubscriptionAPI.checkout(plan.id);
    window.location.href = data.url;
  } catch (error) {
    actionError.value = errorText(error);
    busyPlanId.value = null;
  }
};

// Step 1: ask Stripe how much the change costs, then show the confirmation
const startPlanChange = async plan => {
  actionError.value = '';
  successMessage.value = '';
  busyPlanId.value = plan.id;
  try {
    const { data } = await BillingSubscriptionAPI.changePlanPreview(plan.id);
    pendingChange.value = { plan, preview: data };
  } catch (error) {
    actionError.value = errorText(error);
  } finally {
    busyPlanId.value = null;
  }
};

// Step 2: confirmed -> change the plan now
const confirmPlanChange = async () => {
  const { plan, preview } = pendingChange.value;
  actionError.value = '';
  isChangingPlan.value = true;
  try {
    await BillingSubscriptionAPI.changePlan(plan.id, preview.proration_date);
    pendingChange.value = null;
    successMessage.value = t('CHANGE_SUCCESS', { plan: plan.name });
    await fetchBilling();
  } catch (error) {
    actionError.value = errorText(error);
  } finally {
    isChangingPlan.value = false;
  }
};

const cancelPlanChange = () => {
  pendingChange.value = null;
};

const openPortal = async () => {
  actionError.value = '';
  isOpeningPortal.value = true;
  try {
    const { data } = await BillingSubscriptionAPI.portal();
    window.location.href = data.url;
  } catch (error) {
    actionError.value = errorText(error);
    isOpeningPortal.value = false;
  }
};

onMounted(async () => {
  await fetchBilling();
  // The webhook may arrive a few seconds after Stripe redirects back
  if (checkoutResult.value === 'success') setTimeout(fetchBilling, 4000);

  // Arrived from the pricing page: find out which workspaces could pay, then clear the intention. It is
  // cleared HERE rather than when it was read, so that a refresh on the way through onboarding does not
  // lose it -- by this point the plan is on screen and the URL carries it.
  if (resumePlanId.value) {
    try {
      const { data } = await PendingPlanAPI.get();
      resumeAccounts.value = data?.accounts || [];
      await PendingPlanAPI.clear();
    } catch {
      // A missing or expired intention is not an error: the plan is already named in the URL and the
      // page below works exactly as it does for anyone else.
    }
  }
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="t('LOADING')"
    :no-records-found="!!loadError"
    :no-records-message="loadError"
  >
    <template #header>
      <BaseSettingsHeader :title="t('TITLE')" :description="t('DESCRIPTION')" />
    </template>

    <template #body>
      <section class="grid gap-4">
        <!-- Arrived from the public pricing page. Names the plan, names the workspace that would pay,
             and offers the others. It is a signpost, not a purchase: the Subscribe button on the card
             below is still the only thing that starts a payment. -->
        <div
          v-if="resumePlan && !hasPaidSubscription"
          class="px-4 py-3 text-sm rounded-lg bg-n-brand/10 text-n-slate-12"
        >
          <p class="font-medium">
            {{ t('RESUME_TITLE', { plan: resumePlan.name }) }}
          </p>
          <p class="mt-1 text-n-slate-11">{{ t('RESUME_BODY') }}</p>
          <p v-if="otherResumeAccounts.length" class="mt-2 text-n-slate-11">
            {{ t('RESUME_CHOOSE') }}
          </p>
          <!-- A wrapped row of links rather than a comma-separated sentence: the separator would be raw
               text in the template, and a gap says the same thing in both reading directions. -->
          <span
            v-if="otherResumeAccounts.length"
            class="inline-flex flex-wrap gap-x-3 gap-y-1 mt-1"
          >
            <a
              v-for="account in otherResumeAccounts"
              :key="account.id"
              class="underline text-n-slate-11 hover:text-n-slate-12"
              :href="`/app/accounts/${account.id}/settings/subscription?plan=${resumePlanId}`"
            >
              {{ account.name }}
            </a>
          </span>
        </div>

        <!-- messages -->
        <div
          v-if="checkoutResult === 'success'"
          class="px-4 py-3 text-sm rounded-lg bg-n-teal-3 text-n-teal-11"
        >
          {{ t('CHECKOUT_SUCCESS') }}
        </div>
        <div
          v-else-if="checkoutResult === 'canceled'"
          class="px-4 py-3 text-sm rounded-lg bg-n-alpha-2 text-n-slate-11"
        >
          {{ t('CHECKOUT_CANCELED') }}
        </div>
        <div
          v-if="successMessage"
          class="px-4 py-3 text-sm rounded-lg bg-n-teal-3 text-n-teal-11"
        >
          {{ successMessage }}
        </div>
        <div
          v-if="actionError"
          class="px-4 py-3 text-sm rounded-lg bg-n-ruby-3 text-n-ruby-11"
        >
          {{ actionError }}
        </div>
        <div
          v-if="!isAdmin"
          class="px-4 py-3 text-sm rounded-lg bg-n-amber-3 text-n-amber-11"
        >
          {{ t('ADMIN_ONLY') }}
        </div>

        <!-- plan change confirmation -->
        <div
          v-if="pendingChange"
          class="flex flex-col gap-3 p-5 rounded-xl outline outline-1 outline-n-brand bg-n-solid-2"
        >
          <h3 class="text-base font-medium text-n-slate-12">
            {{ t('CONFIRM_TITLE', { plan: pendingChange.plan.name }) }}
          </h3>
          <p class="text-sm text-n-slate-11">{{ confirmMessage }}</p>
          <div class="flex gap-2">
            <ButtonV4
              sm
              solid
              blue
              :is-loading="isChangingPlan"
              @click="confirmPlanChange"
            >
              {{ t('CONFIRM_BUTTON') }}
            </ButtonV4>
            <ButtonV4
              sm
              faded
              slate
              :disabled="isChangingPlan"
              @click="cancelPlanChange"
            >
              {{ t('CANCEL_BUTTON') }}
            </ButtonV4>
          </div>
        </div>

        <!-- current subscription -->
        <BillingCard
          :title="t('CURRENT')"
          :description="t('MANAGE_BILLING_DESC')"
        >
          <template #action>
            <ButtonV4
              v-if="isAdmin && subscription?.has_billing_account"
              sm
              solid
              blue
              :is-loading="isOpeningPortal"
              @click="openPortal"
            >
              {{ t('MANAGE_BILLING') }}
            </ButtonV4>
          </template>
          <div
            class="grid grid-cols-1 gap-2 sm:grid-cols-3 divide-x divide-n-weak"
          >
            <DetailItem
              :label="t('PLAN')"
              :value="subscription?.plan_name || t('NO_PLAN')"
            />
            <DetailItem :label="t('STATUS')" :value="statusInfo.label" />
            <DetailItem
              v-if="statusInfo.date"
              :label="statusInfo.dateLabel"
              :value="statusInfo.date"
            />
          </div>
        </BillingCard>

        <!-- usage -->
        <BillingCard :title="t('USAGE')" :description="t('USAGE_DESC')">
          <div
            class="grid grid-cols-1 gap-2 divide-x divide-n-weak"
            :class="showsStores ? 'sm:grid-cols-3' : 'sm:grid-cols-2'"
          >
            <DetailItem :label="t('AGENTS')" :value="usageText(usage.agents)" />
            <DetailItem
              :label="t('INBOXES')"
              :value="usageText(usage.inboxes)"
            />
            <DetailItem
              v-if="showsStores"
              :label="t('STORES')"
              :value="usageText(usage.stores)"
            />
          </div>
        </BillingCard>

        <!-- plans -->
        <div class="flex flex-col gap-1 px-1 mt-4">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('PLANS') }}
          </h2>
          <p class="text-sm text-n-slate-11">{{ t('PLANS_DESC') }}</p>
        </div>

        <p v-if="!plans.length" class="px-1 text-sm text-n-slate-11">
          {{ t('NO_PLANS') }}
        </p>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div
            v-for="plan in plans"
            :key="plan.id"
            class="flex flex-col gap-4 p-5 rounded-xl outline outline-1 bg-n-solid-2"
            :class="
              plan.id === subscription?.plan_id || plan.id === resumePlanId
                ? 'outline-n-brand'
                : 'outline-n-container'
            "
          >
            <div class="flex flex-col gap-1">
              <h3 class="text-base font-medium text-n-slate-12">
                {{ plan.name }}
              </h3>
              <p v-if="plan.description" class="text-sm text-n-slate-11">
                {{ plan.description }}
              </p>
            </div>

            <div class="flex items-baseline gap-1">
              <span class="text-2xl font-semibold text-n-slate-12">{{
                formatPrice(plan)
              }}</span>
              <span class="text-sm text-n-slate-11">
                {{ plan.interval === 'year' ? t('PER_YEAR') : t('PER_MONTH') }}
                <template v-if="plan.pricing_type === 'per_agent'">
                  · {{ t('PER_AGENT') }}
                </template>
              </span>
            </div>

            <ul class="flex flex-col gap-1 text-sm text-n-slate-11">
              <li class="flex items-center gap-1.5">
                <span class="i-lucide-check size-3.5 flex-shrink-0" />
                {{ t('AGENTS') }}: {{ limitText(plan.limits?.agents) }}
              </li>
              <li class="flex items-center gap-1.5">
                <span class="i-lucide-check size-3.5 flex-shrink-0" />
                {{ t('INBOXES') }}: {{ limitText(plan.limits?.inboxes) }}
              </li>
              <li v-if="plan.commerce" class="flex items-center gap-1.5">
                <span class="i-lucide-check size-3.5 flex-shrink-0" />
                {{ `${t('STORES')}: ${limitText(plan.limits?.stores)}` }}
              </li>
              <li
                v-for="feature in plan.features"
                :key="feature"
                class="flex items-center gap-1.5"
              >
                <span class="i-lucide-check size-3.5 flex-shrink-0" />
                {{ feature }}
              </li>
            </ul>

            <div v-if="isAdmin" class="mt-auto">
              <!-- current plan -->
              <ButtonV4
                v-if="hasPaidSubscription && plan.id === subscription?.plan_id"
                sm
                faded
                slate
                class="w-full"
                disabled
              >
                {{ t('CURRENT_PLAN') }}
              </ButtonV4>
              <!-- paid subscription -> change plan -->
              <ButtonV4
                v-else-if="hasPaidSubscription"
                sm
                solid
                blue
                class="w-full"
                :is-loading="busyPlanId === plan.id"
                :disabled="
                  !canChangePlan || busyPlanId !== null || !!pendingChange
                "
                @click="startPlanChange(plan)"
              >
                {{ t('CHANGE_PLAN') }}
              </ButtonV4>
              <!-- no paid subscription -> checkout -->
              <ButtonV4
                v-else
                sm
                solid
                blue
                class="w-full"
                :is-loading="busyPlanId === plan.id"
                :disabled="busyPlanId !== null"
                @click="subscribe(plan)"
              >
                {{ t('SUBSCRIBE') }}
              </ButtonV4>
            </div>
          </div>
        </div>
      </section>
    </template>
  </SettingsLayout>
</template>
