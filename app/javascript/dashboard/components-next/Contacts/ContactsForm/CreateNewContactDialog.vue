<script setup>
// Lynomia Contacts, phase B (docs/contacts/03-phase-b.md). The dialog owns the create: the dispatch used to
// live in each of the two parents that mount it, so the header path showed a canned "already in use" line for
// every 422 and the empty-state path showed nothing at all. With one owner there is one catch, one place that
// knows which label the list is filtered by, and one place to offer a way out of a duplicate.
import { ref, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import ContactAPI from 'dashboard/api/contacts';
import BulkActionsAPI from 'dashboard/api/bulkActions';
import {
  contactErrorMessage,
  contactFieldErrors,
  takenIdentityFields,
} from 'dashboard/helper/contactErrors';
import { contactDetailRoute } from 'dashboard/helper/contactRoutes';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';

const emit = defineEmits(['created']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const dialogRef = ref(null);
const contactsFormRef = ref(null);
const contact = ref(null);
const serverErrors = ref({});
const existingContact = ref(null);
const isAddingLabel = ref(false);

const uiFlags = useMapGetter('contacts/getUIFlags');
const isCreatingContact = computed(() => uiFlags.value.isCreating);

// The label the list is filtered by, which is the label a contact created here is meant to have.
const activeLabel = computed(() => route.params.label ?? '');

const existingContactName = computed(
  () => existingContact.value?.name || t('CONTACT_ERRORS.DUPLICATE.UNNAMED')
);

const clearErrors = () => {
  serverErrors.value = {};
  existingContact.value = null;
};

const onFormUpdate = contactItem => {
  contact.value = contactItem;
  // Editing is the user answering the error, so stop marking the fields.
  if (Object.keys(serverErrors.value).length || existingContact.value) {
    clearErrors();
  }
};

// Called directly rather than through the contacts store: `contacts/filter` with `resetState: false` never
// clears its own `isFetching` flag, which would leave this page showing a spinner for good.
const findContactBy = async attribute => {
  const value =
    attribute === 'email' ? contact.value?.email : contact.value?.phoneNumber;
  if (!value) return null;

  try {
    const { data } = await ContactAPI.filter(1, undefined, {
      payload: [
        {
          attribute_key: attribute,
          filter_operator: 'equal_to',
          values: [value],
          attribute_model: 'standard',
          custom_attribute_type: '',
        },
      ],
    });
    // Account-scoped by the server, so a contact in another account is simply not found.
    return data?.payload?.[0] ?? null;
  } catch {
    return null;
  }
};

const offerRecovery = async error => {
  const takenFields = takenIdentityFields(error);
  // Two collided keys can belong to two different contacts, so there is no single one to offer.
  if (takenFields.length !== 1) return;

  existingContact.value = await findContactBy(takenFields[0]);
};

const handleDialogConfirm = async () => {
  if (!contact.value) return;
  clearErrors();

  try {
    const created = await store.dispatch('contacts/create', {
      ...contact.value,
      ...(activeLabel.value ? { labels: [activeLabel.value] } : {}),
    });
    contactsFormRef.value?.resetForm();
    dialogRef.value.close();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.SUCCESS_MESSAGE')
    );
    emit('created', created);
  } catch (error) {
    serverErrors.value = contactFieldErrors(error, t);
    useAlert(contactErrorMessage(error, t));
    await offerRecovery(error);
  }
};

const openExistingContact = () => {
  const { id } = existingContact.value;
  dialogRef.value.close();
  router.push(contactDetailRoute(id, route));
};

// The additive server-side path, so another agent's labels are never replaced by this one's view of them.
const addLabelToExistingContact = async () => {
  isAddingLabel.value = true;
  const name = existingContactName.value;
  try {
    await BulkActionsAPI.create({
      type: 'Contact',
      ids: [existingContact.value.id],
      labels: { add: [activeLabel.value] },
    });
    useAlert(
      t('CONTACT_ERRORS.DUPLICATE.LABEL_ADDED', {
        label: activeLabel.value,
        name,
      })
    );
    existingContact.value = null;
  } catch {
    useAlert(
      t('CONTACT_ERRORS.DUPLICATE.LABEL_FAILED', {
        label: activeLabel.value,
        name,
      })
    );
  } finally {
    isAddingLabel.value = false;
  }
};

const closeDialog = () => {
  clearErrors();
  dialogRef.value.close();
};

defineExpose({ dialogRef, contactsFormRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    @confirm="handleDialogConfirm"
  >
    <ContactsForm
      ref="contactsFormRef"
      is-new-contact
      :server-errors="serverErrors"
      @update="onFormUpdate"
    />
    <div
      v-if="existingContact"
      class="flex flex-col gap-2 p-3 mt-4 rounded-lg bg-n-alpha-2 dark:bg-n-solid-2"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CONTACT_ERRORS.DUPLICATE.TITLE') }}
      </span>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          sm
          variant="ghost"
          color="slate"
          icon="i-lucide-external-link"
          :label="
            t('CONTACT_ERRORS.DUPLICATE.OPEN', { name: existingContactName })
          "
          type="button"
          @click="openExistingContact"
        />
        <Button
          v-if="activeLabel"
          sm
          variant="ghost"
          color="slate"
          icon="i-lucide-tag"
          :label="
            t('CONTACT_ERRORS.DUPLICATE.ADD_LABEL', {
              label: activeLabel,
              name: existingContactName,
            })
          "
          :is-loading="isAddingLabel"
          :disabled="isAddingLabel"
          type="button"
          @click="addLabelToExistingContact"
        />
      </div>
    </div>
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          :label="t('DIALOG.BUTTONS.CANCEL')"
          variant="link"
          type="reset"
          class="h-10 hover:!no-underline hover:text-n-brand"
          @click="closeDialog"
        />
        <Button
          type="submit"
          :label="
            t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.SAVE_CONTACT')
          "
          color="blue"
          :disabled="contactsFormRef?.isFormInvalid"
          :is-loading="isCreatingContact"
        />
      </div>
    </template>
  </Dialog>
</template>
