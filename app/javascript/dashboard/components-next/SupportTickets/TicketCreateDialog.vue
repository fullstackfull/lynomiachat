<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import SupportTicketsAPI from 'dashboard/api/supportTickets';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import {
  TICKET_CATEGORIES,
  TICKET_DESCRIPTION_MAX_LENGTH,
  TICKET_PRIORITIES,
  TICKET_TITLE_MAX_LENGTH,
} from 'dashboard/constants/supportTickets';

// Opening a case. `status` is deliberately absent: a new case always opens, and the server does not accept one.
// The three links are prefilled rather than chosen when the dialog is opened from a conversation, which is where
// most cases start -- the agent is already looking at the customer, so asking them to pick one again is a
// question with a known answer.
const props = defineProps({
  conversationId: {
    type: [Number, String],
    default: null,
  },
  contactId: {
    type: [Number, String],
    default: null,
  },
  inboxId: {
    type: [Number, String],
    default: null,
  },
  agents: {
    type: Array,
    default: () => [],
  },
  teams: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['created']);

const { t } = useI18n();
const { isAdmin } = useAdmin();

const DEFAULT_CATEGORY = 'other';
const DEFAULT_PRIORITY = 'medium';

const dialogRef = ref(null);
const isCreating = ref(false);
const slaPolicies = ref([]);

const emptyForm = () => ({
  title: '',
  description: '',
  category: DEFAULT_CATEGORY,
  priority: DEFAULT_PRIORITY,
  assignee_id: '',
  team_id: '',
  sla_policy_id: '',
});

const form = ref(emptyForm());

const categoryOptions = computed(() =>
  TICKET_CATEGORIES.map(value => ({
    value,
    label: t(`SUPPORT_TICKETS.ENUMS.CATEGORY.${value.toUpperCase()}`),
  }))
);

const priorityOptions = computed(() =>
  TICKET_PRIORITIES.map(value => ({
    value,
    label: t(`SUPPORT_TICKETS.ENUMS.PRIORITY.${value.toUpperCase()}`),
  }))
);

const agentOptions = computed(() => [
  { value: '', label: t('SUPPORT_TICKETS.CREATE.FIELDS.UNASSIGNED') },
  ...props.agents.map(agent => ({ value: agent.id, label: agent.name })),
]);

const teamOptions = computed(() => [
  { value: '', label: t('SUPPORT_TICKETS.CREATE.FIELDS.NO_TEAM') },
  ...props.teams.map(team => ({ value: team.id, label: team.name })),
]);

const slaPolicyOptions = computed(() => [
  { value: '', label: t('SUPPORT_TICKETS.CREATE.FIELDS.NO_SLA_POLICY') },
  ...slaPolicies.value.map(policy => ({
    value: policy.id,
    label: policy.name,
  })),
]);

const isSubmitDisabled = computed(() => {
  const title = form.value.title.trim();
  return !title || title.length > TICKET_TITLE_MAX_LENGTH;
});

// Administrators only, because that is who may read the policy list. An agent opening a case gets no SLA field
// rather than a select that would answer with a 403.
const loadSlaPolicies = async () => {
  if (!isAdmin.value) return;
  try {
    const response = await SupportTicketsAPI.getSlaPolicies();
    slaPolicies.value = response.data.payload || [];
  } catch {
    // The case can still be opened without a policy, so a failure here is not worth interrupting the form for.
    slaPolicies.value = [];
  }
};

const open = () => {
  form.value = emptyForm();
  loadSlaPolicies();
  dialogRef.value?.open();
};

// Only the fields the operator actually filled are sent: an empty string would be a request to clear a link
// that was never set, and the three prefilled links are sent exactly as the caller gave them.
const payload = () => {
  const ticket = {
    title: form.value.title.trim(),
    category: form.value.category,
    priority: form.value.priority,
  };
  if (form.value.description.trim()) {
    ticket.description = form.value.description.trim();
  }
  if (form.value.assignee_id) ticket.assignee_id = form.value.assignee_id;
  if (form.value.team_id) ticket.team_id = form.value.team_id;
  if (form.value.sla_policy_id) {
    ticket.sla_policy_id = form.value.sla_policy_id;
  }
  if (props.conversationId) ticket.conversation_id = props.conversationId;
  if (props.contactId) ticket.contact_id = props.contactId;
  if (props.inboxId) ticket.inbox_id = props.inboxId;
  return ticket;
};

// A refused request carries a message already written for a human; it is shown as it came rather than reworded.
const onConfirm = async () => {
  isCreating.value = true;
  try {
    const response = await SupportTicketsAPI.createTicket(payload());
    useAlert(t('SUPPORT_TICKETS.CREATE.SUCCESS'));
    emit('created', response.data.payload);
    dialogRef.value?.close();
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('SUPPORT_TICKETS.CREATE.ERROR')
    );
  } finally {
    isCreating.value = false;
  }
};

defineExpose({ open, dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="2xl"
    overflow-y-auto
    :title="t('SUPPORT_TICKETS.CREATE.TITLE')"
    :description="t('SUPPORT_TICKETS.CREATE.DESCRIPTION')"
    :confirm-button-label="t('SUPPORT_TICKETS.CREATE.SUBMIT')"
    :is-loading="isCreating"
    :disable-confirm-button="isSubmitDisabled"
    @confirm="onConfirm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.title"
        :label="t('SUPPORT_TICKETS.CREATE.FIELDS.SUBJECT')"
        :placeholder="t('SUPPORT_TICKETS.CREATE.FIELDS.SUBJECT_PLACEHOLDER')"
      />

      <TextArea
        v-model="form.description"
        :label="t('SUPPORT_TICKETS.CREATE.FIELDS.DESCRIPTION')"
        :placeholder="
          t('SUPPORT_TICKETS.CREATE.FIELDS.DESCRIPTION_PLACEHOLDER')
        "
        :max-length="TICKET_DESCRIPTION_MAX_LENGTH"
        auto-height
      />

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1 text-label text-n-slate-12">
          {{ t('SUPPORT_TICKETS.CREATE.FIELDS.CATEGORY') }}
          <Select
            v-model="form.category"
            class="!w-full [&>select]:w-full"
            :options="categoryOptions"
          />
        </label>

        <label class="flex flex-col gap-1 text-label text-n-slate-12">
          {{ t('SUPPORT_TICKETS.CREATE.FIELDS.PRIORITY') }}
          <Select
            v-model="form.priority"
            class="!w-full [&>select]:w-full"
            :options="priorityOptions"
          />
        </label>

        <label class="flex flex-col gap-1 text-label text-n-slate-12">
          {{ t('SUPPORT_TICKETS.CREATE.FIELDS.ASSIGNEE') }}
          <Select
            v-model="form.assignee_id"
            class="!w-full [&>select]:w-full"
            :options="agentOptions"
          />
        </label>

        <label class="flex flex-col gap-1 text-label text-n-slate-12">
          {{ t('SUPPORT_TICKETS.CREATE.FIELDS.TEAM') }}
          <Select
            v-model="form.team_id"
            class="!w-full [&>select]:w-full"
            :options="teamOptions"
          />
        </label>

        <label
          v-if="isAdmin"
          class="flex flex-col gap-1 text-label text-n-slate-12 sm:col-span-2"
        >
          {{ t('SUPPORT_TICKETS.CREATE.FIELDS.SLA_POLICY') }}
          <Select
            v-model="form.sla_policy_id"
            class="!w-full [&>select]:w-full"
            :options="slaPolicyOptions"
          />
        </label>
      </div>
    </div>
  </Dialog>
</template>
