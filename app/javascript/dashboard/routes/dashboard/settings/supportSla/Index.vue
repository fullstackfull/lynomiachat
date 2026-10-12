<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SupportTicketsAPI from 'dashboard/api/supportTickets';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import SlaPolicyDialog from './SlaPolicyDialog.vue';
import { SECONDS_PER_MINUTE } from 'dashboard/constants/supportTickets';

// SLA targets for support cases (docs/p9/03-sla-workflow.md). Administrator-only, because a target is an
// account-wide commitment rather than a per-case decision -- which is also why the endpoints sit behind the
// administrator boundary and not the ticket policy.
const { t } = useI18n();

const MINUTES_PER_HOUR = 60;
const HOURS_PER_DAY = 24;

const policies = ref([]);
const isFetching = ref(true);
const selectedPolicy = ref(null);
const deletingId = ref(null);
const showDeleteConfirmation = ref(false);
const policyDialogRef = ref(null);

const tableHeaders = computed(() => [
  t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.NAME'),
  t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.FIRST_RESPONSE'),
  t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.RESOLUTION'),
  t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.BUSINESS_HOURS'),
  t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.ACTIONS'),
]);

// Seconds in, the largest whole unit out: a reader comparing two policies should not be counting zeroes.
const formatThreshold = seconds => {
  if (!seconds) return t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.NO_THRESHOLD');

  const minutes = Math.floor(seconds / SECONDS_PER_MINUTE);
  if (minutes % (MINUTES_PER_HOUR * HOURS_PER_DAY) === 0) {
    return t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.DAYS', {
      count: minutes / (MINUTES_PER_HOUR * HOURS_PER_DAY),
    });
  }
  if (minutes % MINUTES_PER_HOUR === 0) {
    return t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.HOURS', {
      count: minutes / MINUTES_PER_HOUR,
    });
  }
  return t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.MINUTES', { count: minutes });
};

const deleteMessage = computed(() => ` ${selectedPolicy.value?.name}?`);

const fetchPolicies = async () => {
  isFetching.value = true;
  try {
    const response = await SupportTicketsAPI.getSlaPolicies();
    policies.value = response.data.payload || [];
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('SUPPORT_TICKETS.SLA_SETTINGS.FETCH_ERROR')
    );
  } finally {
    isFetching.value = false;
  }
};

const openCreate = () => {
  selectedPolicy.value = null;
  policyDialogRef.value?.open();
};

const openEdit = policy => {
  selectedPolicy.value = policy;
  policyDialogRef.value?.open();
};

const openDelete = policy => {
  selectedPolicy.value = policy;
  showDeleteConfirmation.value = true;
};

const closeDelete = () => {
  showDeleteConfirmation.value = false;
};

// Deleting a policy nullifies the link on every case that used it; the due times already computed stay as they
// are, because they were a commitment made when the policy was attached.
const confirmDelete = async () => {
  const policy = selectedPolicy.value;
  closeDelete();
  deletingId.value = policy.id;
  try {
    await SupportTicketsAPI.deleteSlaPolicy(policy.id);
    useAlert(t('SUPPORT_TICKETS.SLA_SETTINGS.DELETE.SUCCESS'));
    await fetchPolicies();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('SUPPORT_TICKETS.SLA_SETTINGS.DELETE.ERROR')
    );
  } finally {
    deletingId.value = null;
  }
};

onMounted(fetchPolicies);
</script>

<template>
  <SettingsLayout
    :no-records-found="!policies.length && !isFetching"
    :no-records-message="t('SUPPORT_TICKETS.SLA_SETTINGS.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('SUPPORT_TICKETS.SLA_SETTINGS.HEADER')"
        :description="t('SUPPORT_TICKETS.SLA_SETTINGS.DESCRIPTION')"
      >
        <template v-if="policies.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{
              t('SUPPORT_TICKETS.SLA_SETTINGS.COUNT', { n: policies.length })
            }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="t('SUPPORT_TICKETS.SLA_SETTINGS.NEW_POLICY')"
            icon="i-lucide-plus"
            size="sm"
            @click="openCreate"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #emptyState>
      <div class="flex flex-col items-center gap-4 py-20">
        <p class="m-0 text-center text-body-para text-n-slate-11">
          {{ t('SUPPORT_TICKETS.SLA_SETTINGS.LIST.404') }}
        </p>
        <Button
          :label="t('SUPPORT_TICKETS.SLA_SETTINGS.NEW_POLICY')"
          icon="i-lucide-plus"
          size="sm"
          @click="openCreate"
        />
      </div>
    </template>

    <template #body>
      <BaseTable
        sticky-header
        align-last-column-end
        :headers="tableHeaders"
        :items="policies"
        :loading="isFetching"
        :loading-message="t('SUPPORT_TICKETS.SLA_SETTINGS.LOADING')"
        :column-classes="['', '', '', 'hidden md:table-cell', '']"
      >
        <template #row="{ items }">
          <BaseTableRow v-for="policy in items" :key="policy.id" :item="policy">
            <template #default>
              <BaseTableCell>
                <div class="flex flex-col">
                  <span class="text-body-main text-n-slate-12">
                    {{ policy.name }}
                  </span>
                  <span
                    v-if="policy.description"
                    class="text-label-small text-n-slate-11"
                  >
                    {{ policy.description }}
                  </span>
                </div>
              </BaseTableCell>

              <BaseTableCell>
                <span class="whitespace-nowrap text-body-main text-n-slate-11">
                  {{ formatThreshold(policy.first_response_time_threshold) }}
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span class="whitespace-nowrap text-body-main text-n-slate-11">
                  {{ formatThreshold(policy.resolution_time_threshold) }}
                </span>
              </BaseTableCell>

              <BaseTableCell class="hidden md:table-cell">
                <span class="text-body-main text-n-slate-11">
                  {{
                    policy.only_during_business_hours
                      ? t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.BUSINESS_ONLY')
                      : t('SUPPORT_TICKETS.SLA_SETTINGS.TABLE.AROUND_THE_CLOCK')
                  }}
                </span>
              </BaseTableCell>

              <BaseTableCell align="end">
                <div class="flex justify-end flex-shrink-0 gap-3">
                  <Button
                    v-tooltip.top="t('SUPPORT_TICKETS.SLA_SETTINGS.EDIT')"
                    :aria-label="t('SUPPORT_TICKETS.SLA_SETTINGS.EDIT')"
                    icon="i-lucide-pencil"
                    slate
                    sm
                    @click="openEdit(policy)"
                  />
                  <Button
                    v-tooltip.top="
                      t('SUPPORT_TICKETS.SLA_SETTINGS.DELETE.BUTTON')
                    "
                    :aria-label="
                      t('SUPPORT_TICKETS.SLA_SETTINGS.DELETE.BUTTON')
                    "
                    icon="i-lucide-trash-2"
                    slate
                    sm
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    :is-loading="deletingId === policy.id"
                    @click="openDelete(policy)"
                  />
                </div>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <SlaPolicyDialog
      ref="policyDialogRef"
      :policy="selectedPolicy"
      @saved="fetchPolicies"
    />

    <woot-delete-modal
      v-model:show="showDeleteConfirmation"
      :on-close="closeDelete"
      :on-confirm="confirmDelete"
      :title="t('SUPPORT_TICKETS.SLA_SETTINGS.DELETE.CONFIRM.TITLE')"
      :message="t('SUPPORT_TICKETS.SLA_SETTINGS.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="t('SUPPORT_TICKETS.SLA_SETTINGS.DELETE.CONFIRM.YES')"
      :reject-text="t('SUPPORT_TICKETS.SLA_SETTINGS.DELETE.CONFIRM.NO')"
    />
  </SettingsLayout>
</template>
