<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import FlowsAPI from 'dashboard/api/flows';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { reasonLabel } from '../flowGraph';

// Test Mode (docs/flow-builder/05-runtime-and-session.md §test mode): the saved draft run by the real runtime for a
// test contact and rolled back, so nothing is sent, stored or posted. Each step replays the tester's whole input list;
// a tap on a button or list row sends its option id as WhatsApp does.
const props = defineProps({
  flowId: { type: Number, required: true },
  beforeRun: { type: Function, required: true },
});
const emit = defineEmits(['close', 'node']);

const { t } = useI18n();
const MAX_INPUTS = 30;

const inputs = ref([]);
const result = ref(null);
const draft = ref('');
const isRunning = ref(false);
const error = ref('');

const transcript = computed(() => result.value?.transcript || []);
const session = computed(() => result.value?.session);
const path = computed(() =>
  (result.value?.trace || [])
    .filter(entry => entry.event === 'flow.node.executed')
    .map(entry => `${entry.node_id} → ${entry.result}`)
);
const lastBotIndex = computed(() =>
  transcript.value.map(entry => entry.from).lastIndexOf('bot')
);
const sessionState = computed(() => {
  if (!result.value) return '';
  if (!session.value) return t('FLOW_BUILDER.TEST.NOT_STARTED');
  const reason = session.value.end_reason || session.value.failure_code;
  return [
    t(`FLOW_BUILDER.SESSION_STATUS.${session.value.status.toUpperCase()}`),
    reason ? reasonLabel(t, reason) : '',
  ]
    .filter(Boolean)
    .join(' · ');
});

const run = async next => {
  if (next.length > MAX_INPUTS) {
    error.value = t('FLOW_BUILDER.TEST.TOO_LONG');
    return;
  }
  isRunning.value = true;
  error.value = '';
  try {
    await props.beforeRun();
    const { data } = await FlowsAPI.simulate(props.flowId, next);
    inputs.value = next;
    result.value = data;
    emit('node', data.session?.current_node_id || null);
  } catch (e) {
    const code = e?.response?.data?.errors?.[0]?.code;
    error.value = code
      ? t(`FLOW_BUILDER.ERRORS.${code.toUpperCase()}`, { detail: '' })
      : t('FLOW_BUILDER.TEST.FAILED');
  } finally {
    isRunning.value = false;
  }
};

const send = (text, replyId = null) => {
  const value = text.trim();
  if (!value) return;
  draft.value = '';
  run([
    ...inputs.value,
    replyId ? { text: value, reply_id: replyId } : { text: value },
  ]);
};
const fireTimer = () => run([...inputs.value, { timer: true }]);
const restart = () => {
  inputs.value = [];
  result.value = null;
  error.value = '';
  emit('node', null);
};
</script>

<template>
  <aside
    class="absolute inset-0 z-10 flex flex-col w-full md:static md:w-96 shrink-0 border-s border-n-weak bg-n-solid-1"
    data-test-id="flow-test-panel"
  >
    <header class="flex items-center gap-2 px-4 py-3 border-b border-n-weak">
      <h2 class="flex-1 m-0 text-sm font-medium text-n-slate-12">
        {{ t('FLOW_BUILDER.TEST.TITLE') }}
      </h2>
      <NextButton
        v-tooltip.top="t('FLOW_BUILDER.TEST.RESTART')"
        icon="i-lucide-rotate-ccw"
        slate
        ghost
        sm
        @click="restart"
      />
      <NextButton icon="i-lucide-x" slate ghost sm @click="emit('close')" />
    </header>
    <p class="px-4 pt-3 m-0 text-xs text-n-slate-11">
      {{ t('FLOW_BUILDER.TEST.HINT') }}
    </p>
    <div class="flex flex-col flex-1 gap-2 p-4 overflow-y-auto">
      <div
        v-for="(entry, index) in transcript"
        :key="index"
        class="flex flex-col max-w-[85%] gap-1"
        :class="entry.from === 'customer' ? 'self-end items-end' : 'self-start'"
        :data-test-id="`flow-test-${entry.from}`"
      >
        <p
          dir="auto"
          class="px-3 py-2 m-0 text-sm whitespace-pre-wrap break-words rounded-xl"
          :class="{
            'bg-n-blue-9 text-white': entry.from === 'customer',
            'bg-n-alpha-2 text-n-slate-12': entry.from === 'bot',
            'bg-n-amber-3 text-n-amber-11 text-xs': entry.from === 'note',
          }"
        >
          {{ entry.text }}
        </p>
        <span
          v-if="entry.template"
          class="text-xs text-n-slate-11"
          data-test-id="flow-test-template"
        >
          {{ t('FLOW_BUILDER.TEST.TEMPLATE', { name: entry.template }) }}
        </span>
        <span v-if="entry.list_button" class="text-xs text-n-slate-11">
          {{ entry.list_button }}
        </span>
        <div v-if="entry.items?.length" class="flex flex-wrap gap-1">
          <NextButton
            v-for="item in entry.items"
            :key="item.value"
            :label="item.title"
            blue
            faded
            xs
            :disabled="isRunning || index !== lastBotIndex"
            :data-test-id="`flow-test-option-${item.value}`"
            @click="send(item.title, item.value)"
          />
        </div>
      </div>
      <p
        v-if="sessionState"
        class="m-0 text-xs text-n-slate-11"
        data-test-id="flow-test-state"
      >
        {{ sessionState }}
      </p>
      <details v-if="path.length" class="text-xs text-n-slate-11">
        <summary class="cursor-pointer">
          {{ t('FLOW_BUILDER.TEST.PATH') }}
        </summary>
        <ol class="m-0 mt-1 ps-4" dir="ltr">
          <li v-for="(step, index) in path" :key="index">{{ step }}</li>
        </ol>
      </details>
      <p v-if="error" class="m-0 text-xs text-n-ruby-11">{{ error }}</p>
    </div>
    <footer class="flex flex-col gap-2 p-3 border-t border-n-weak">
      <NextButton
        v-if="session?.timer"
        icon="i-lucide-timer"
        :label="t('FLOW_BUILDER.TEST.FIRE_TIMER')"
        slate
        faded
        sm
        :disabled="isRunning"
        @click="fireTimer"
      />
      <form class="flex items-center gap-2" @submit.prevent="send(draft)">
        <Input
          v-model="draft"
          class="flex-1"
          :placeholder="t('FLOW_BUILDER.TEST.PLACEHOLDER')"
          data-test-id="flow-test-input"
        />
        <NextButton
          type="submit"
          icon="i-lucide-send-horizontal"
          :is-loading="isRunning"
          :disabled="!draft.trim()"
          sm
        />
      </form>
    </footer>
  </aside>
</template>
