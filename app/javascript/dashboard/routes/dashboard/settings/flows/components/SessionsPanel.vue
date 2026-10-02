<script setup>
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import FlowsAPI from 'dashboard/api/flows';
import Select from 'dashboard/components-next/select/Select.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { reasonLabel } from '../flowGraph';

// The execution inspector: the flow's latest sessions, where each is or how it ended. Node ids and states only; the
// conversation itself is one click away for those who may open it.
const props = defineProps({
  flowId: { type: Number, required: true },
  accountId: { type: Number, required: true },
});
const emit = defineEmits(['close', 'node']);

const { t } = useI18n();
const STATUSES = [
  'active',
  'waiting',
  'handed_off',
  'completed',
  'failed',
  'cancelled',
];

const sessions = ref([]);
const status = ref('');
const isLoading = ref(false);
const statusOptions = [
  { value: '', label: t('FLOW_BUILDER.SESSIONS.ALL') },
  ...STATUSES.map(value => ({
    value,
    label: t(`FLOW_BUILDER.SESSION_STATUS.${value.toUpperCase()}`),
  })),
];

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await FlowsAPI.sessions(props.flowId, status.value);
    sessions.value = data.payload;
  } finally {
    isLoading.value = false;
  }
};

const reason = session => {
  const code = session.end_reason || session.failure_code;
  return code ? reasonLabel(t, code) : '';
};
const link = session =>
  frontendURL(
    conversationUrl({ accountId: props.accountId, id: session.conversation_id })
  );

onMounted(load);
watch(status, load);
</script>

<template>
  <aside
    class="absolute inset-0 z-10 flex flex-col w-full md:static md:w-96 shrink-0 border-s border-n-weak bg-n-solid-1"
    data-test-id="flow-sessions-panel"
  >
    <header class="flex items-center gap-2 px-4 py-3 border-b border-n-weak">
      <h2 class="flex-1 m-0 text-sm font-medium text-n-slate-12">
        {{ t('FLOW_BUILDER.SESSIONS.TITLE') }}
      </h2>
      <NextButton
        icon="i-lucide-refresh-cw"
        slate
        ghost
        sm
        :is-loading="isLoading"
        @click="load"
      />
      <NextButton icon="i-lucide-x" slate ghost sm @click="emit('close')" />
    </header>
    <div class="px-4 pt-3">
      <Select v-model="status" :options="statusOptions" />
    </div>
    <p
      v-if="!sessions.length && !isLoading"
      class="px-4 py-3 m-0 text-sm text-n-slate-11"
    >
      {{ t('FLOW_BUILDER.SESSIONS.EMPTY') }}
    </p>
    <ul class="flex flex-col gap-2 p-4 m-0 overflow-y-auto list-none">
      <li
        v-for="session in sessions"
        :key="session.id"
        class="flex flex-col gap-1 p-3 rounded-lg cursor-pointer bg-n-alpha-1 hover:bg-n-alpha-2"
        @click="emit('node', session.current_node_id)"
      >
        <div class="flex items-center gap-2 text-sm">
          <span class="font-medium text-n-slate-12">
            {{
              t(`FLOW_BUILDER.SESSION_STATUS.${session.status.toUpperCase()}`)
            }}
          </span>
          <a
            :href="link(session)"
            class="text-n-blue-11 ms-auto"
            target="_blank"
            rel="noopener noreferrer"
            @click.stop
          >
            {{ `#${session.conversation_id}` }}
          </a>
        </div>
        <span class="text-xs text-n-slate-11">
          {{
            t('FLOW_BUILDER.SESSIONS.DETAIL', {
              node: session.current_node_id,
              version: session.version,
              steps: session.steps_count,
            })
          }}
        </span>
        <span v-if="reason(session)" class="text-xs text-n-slate-11">
          {{ reason(session) }}
        </span>
        <span class="text-xs text-n-slate-10">
          {{ new Date(session.updated_at).toLocaleString() }}
        </span>
      </li>
    </ul>
  </aside>
</template>
