<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Everything this customer can be reached at, in one place (docs/p10/05-omnichannel-customer-360.md).
//
// Two sections, from two different sources, deliberately not merged into one list: the contact's own phone
// number and email address are its PRIMARY fields and unique per account, while the rest are linked identities
// in `contact_identities`. Saying which is which is the point -- a primary field is what an outgoing
// conversation uses, a linked identity is what an incoming message is matched against.
//
// Nothing here guesses. The server refuses a value another contact owns and names that contact, and this shows
// the refusal rather than offering to merge.
const props = defineProps({
  contact: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
});

const { t } = useI18n();

const IDENTITY_TYPES = ['phone', 'email'];

const identities = ref([]);
const isLoading = ref(false);
const hasLoadedOnce = ref(false);
const isSaving = ref(false);
const errorMessage = ref('');
const newType = ref('phone');
const newValue = ref('');

const primaryFields = computed(() =>
  [
    { type: 'phone', value: props.contact.phone_number },
    { type: 'email', value: props.contact.email },
  ].filter(field => Boolean(field.value))
);

const isEmpty = computed(
  () => primaryFields.value.length === 0 && identities.value.length === 0
);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await ContactAPI.getIdentities(props.contact.id);
    identities.value = data.payload ?? [];
  } catch (error) {
    // A 404 means the account does not have the feature; the tab is not offered in that case, so anything
    // reaching here is worth showing rather than swallowing.
    errorMessage.value =
      error.response?.data?.error ??
      t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.LOAD_ERROR');
  } finally {
    isLoading.value = false;
    hasLoadedOnce.value = true;
  }
};

const link = async () => {
  if (!newValue.value.trim()) return;
  isSaving.value = true;
  errorMessage.value = '';
  try {
    await ContactAPI.linkIdentity(props.contact.id, {
      identityType: newType.value,
      value: newValue.value.trim(),
    });
    newValue.value = '';
    await load();
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.LINKED'));
  } catch (error) {
    errorMessage.value =
      error.response?.data?.error ??
      t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.LINK_ERROR');
  } finally {
    isSaving.value = false;
  }
};

const unlink = async identity => {
  errorMessage.value = '';
  try {
    await ContactAPI.unlinkIdentity(props.contact.id, identity.id);
    await load();
    useAlert(t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.UNLINKED'));
  } catch (error) {
    errorMessage.value =
      error.response?.data?.error ??
      t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.UNLINK_ERROR');
  }
};

// Static keys rather than `t(`...TYPE.${type}`)`: a dynamic key cannot be checked against the locale files,
// and the linter is right to say so.
const typeLabels = computed(() => ({
  phone: t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.TYPE.PHONE'),
  email: t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.TYPE.EMAIL'),
}));

const placeholders = computed(() => ({
  phone: t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.PLACEHOLDER.PHONE'),
  email: t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.PLACEHOLDER.EMAIL'),
}));

const sourceLabel = identity =>
  identity.source === 'merged'
    ? t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.SOURCE.MERGED')
    : t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.SOURCE.AGENT_LINKED');

onMounted(load);
</script>

<template>
  <div class="flex flex-col gap-4 px-6 pb-6">
    <p class="mb-0 text-sm text-n-slate-11">
      {{ t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.DESCRIPTION') }}
    </p>

    <div v-if="isLoading && !hasLoadedOnce" class="flex justify-center py-4">
      <Spinner />
    </div>

    <template v-else>
      <section v-if="primaryFields.length" class="flex flex-col gap-2">
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.PRIMARY_TITLE') }}
        </h4>
        <ul class="flex flex-col gap-1 m-0 list-none">
          <li
            v-for="field in primaryFields"
            :key="`primary-${field.type}`"
            class="flex items-center justify-between gap-2 text-sm"
            data-test-id="primary-identity"
          >
            <bdi dir="auto" class="truncate text-n-slate-12">
              {{ field.value }}
            </bdi>
            <span class="text-xs text-n-slate-10">
              {{ typeLabels[field.type] }}
            </span>
          </li>
        </ul>
      </section>

      <section v-if="identities.length" class="flex flex-col gap-2">
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.LINKED_TITLE') }}
        </h4>
        <ul class="flex flex-col gap-1 m-0 list-none">
          <li
            v-for="identity in identities"
            :key="identity.id"
            class="flex items-center justify-between gap-2 text-sm"
            data-test-id="linked-identity"
          >
            <bdi dir="auto" class="truncate text-n-slate-12">
              {{ identity.value }}
            </bdi>
            <span class="flex items-center gap-2 shrink-0">
              <span class="text-xs text-n-slate-10">
                {{ sourceLabel(identity) }}
              </span>
              <Button
                v-if="canManage"
                :label="t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.UNLINK')"
                variant="link"
                color="ruby"
                size="sm"
                @click="unlink(identity)"
              />
            </span>
          </li>
        </ul>
      </section>

      <p
        v-if="isEmpty"
        class="mb-0 text-sm text-n-slate-10"
        data-test-id="identities-empty"
      >
        {{ t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.EMPTY_STATE') }}
      </p>

      <section v-if="canManage" class="flex flex-col gap-2">
        <h4 class="mb-0 text-sm font-medium text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.ADD_TITLE') }}
        </h4>
        <div class="flex gap-2">
          <Button
            v-for="type in IDENTITY_TYPES"
            :key="type"
            :label="typeLabels[type]"
            :variant="newType === type ? 'solid' : 'faded'"
            color="slate"
            size="sm"
            @click="newType = type"
          />
        </div>
        <Input
          v-model="newValue"
          :placeholder="placeholders[newType]"
          size="sm"
          @enter="link"
        />
        <Button
          :label="t('CONTACTS_LAYOUT.SIDEBAR.IDENTITIES.LINK')"
          :is-loading="isSaving"
          :disabled="isSaving || !newValue.trim()"
          variant="solid"
          color="blue"
          size="sm"
          class="self-start"
          @click="link"
        />
      </section>

      <p v-if="errorMessage" class="mb-0 text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>
    </template>
  </div>
</template>
