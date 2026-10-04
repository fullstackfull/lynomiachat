<script setup>
import { ref, computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { contactDetailRoute } from 'dashboard/helper/contactRoutes';
import { contactErrorMessage } from 'dashboard/helper/contactErrors';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import ContactsCard from 'dashboard/components-next/Contacts/ContactsCard/ContactsCard.vue';

const props = defineProps({
  contacts: { type: Array, required: true },
  selectedContactIds: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['toggleContact']);

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const route = useRoute();

const uiFlags = useMapGetter('contacts/getUIFlags');
const isUpdating = computed(() => uiFlags.value.isUpdating);
const expandedCardId = ref(null);
const hoveredAvatarId = ref(null);

const selectedIdsSet = computed(() => new Set(props.selectedContactIds || []));

const updateContact = async updatedData => {
  try {
    await store.dispatch('contacts/update', updatedData);
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(contactErrorMessage(error, t));
  }
};

const onClickViewDetails = async id => {
  await router.push(contactDetailRoute(id, route));
};

const toggleExpanded = id => {
  expandedCardId.value = expandedCardId.value === id ? null : id;
};

const isSelected = id => selectedIdsSet.value.has(id);

const shouldShowSelection = id => {
  return hoveredAvatarId.value === id || isSelected(id);
};

const handleSelect = (id, value) => {
  emit('toggleContact', { id, value });
};

const handleAvatarHover = (id, isHovered) => {
  hoveredAvatarId.value = isHovered ? id : null;
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div v-for="contact in contacts" :key="contact.id" class="relative">
      <ContactsCard
        :id="contact.id"
        :name="contact.name"
        :email="contact.email"
        :company-id="contact.companyId"
        :thumbnail="contact.thumbnail"
        :phone-number="contact.phoneNumber"
        :additional-attributes="contact.additionalAttributes"
        :availability-status="contact.availabilityStatus"
        :is-expanded="expandedCardId === contact.id"
        :is-updating="isUpdating"
        :selectable="shouldShowSelection(contact.id)"
        :is-selected="isSelected(contact.id)"
        @toggle="toggleExpanded(contact.id)"
        @update-contact="updateContact"
        @show-contact="onClickViewDetails"
        @select="value => handleSelect(contact.id, value)"
        @avatar-hover="value => handleAvatarHover(contact.id, value)"
      />
    </div>
  </div>
</template>
