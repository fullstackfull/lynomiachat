<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime, messageTimestamp } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  TICKET_EVENT_FALLBACK_ICON,
  TICKET_EVENT_ICONS,
  TICKET_NOTE_EVENT_TYPE,
  TICKET_NOTE_MAX_LENGTH,
} from 'dashboard/constants/supportTickets';

// A case's history, internal notes included, in one order. The server records every change as a typed event
// with the ids and enum values it changed between, so this reads the trail rather than parsing prose -- which
// is exactly what a conversation's activity messages cannot offer.
const props = defineProps({
  // Oldest first, as the endpoint returns them: a timeline is read downwards.
  events: {
    type: Array,
    default: () => [],
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  hasMore: {
    type: Boolean,
    default: false,
  },
  isSaving: {
    type: Boolean,
    default: false,
  },
  canAddNote: {
    type: Boolean,
    default: true,
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

const emit = defineEmits(['loadMore', 'addNote']);

const { t } = useI18n();

const note = ref('');

// Which vocabulary each event's `from`/`to` pair is spoken in. An event type absent from this map carries no
// change line, because its `data` is a timestamp or an id that means nothing on its own.
const ENUM_SCOPES = {
  status_changed: 'STATUS',
  resolved: 'STATUS',
  reopened: 'STATUS',
  closed: 'STATUS',
  priority_changed: 'PRIORITY',
  category_changed: 'CATEGORY',
};

const agentNames = computed(() =>
  Object.fromEntries(props.agents.map(agent => [agent.id, agent.name]))
);

const teamNames = computed(() =>
  Object.fromEntries(props.teams.map(team => [team.id, team.name]))
);

const valueLabel = (event, value) => {
  if (value === null || value === undefined || value === '') return '';
  if (event.event_type === 'assigned') {
    return agentNames.value[value] || String(value);
  }
  if (event.event_type === 'team_changed') {
    return teamNames.value[value] || String(value);
  }
  const scope = ENUM_SCOPES[event.event_type];
  if (!scope) return '';
  return t(`SUPPORT_TICKETS.ENUMS.${scope}.${String(value).toUpperCase()}`);
};

const changeLine = event => {
  const from = valueLabel(event, event.data?.from);
  const to = valueLabel(event, event.data?.to);
  if (from && to) {
    return t('SUPPORT_TICKETS.DETAIL.HISTORY.CHANGE', { from, to });
  }
  if (to) return t('SUPPORT_TICKETS.DETAIL.HISTORY.SET', { to });
  if (from) return t('SUPPORT_TICKETS.DETAIL.HISTORY.CLEARED', { from });
  return '';
};

const entries = computed(() =>
  props.events.map(event => ({
    ...event,
    icon: TICKET_EVENT_ICONS[event.event_type] || TICKET_EVENT_FALLBACK_ICON,
    // An event type the server adds later still renders: its own key is shown rather than an empty label.
    title: t(
      `SUPPORT_TICKETS.EVENTS.${event.event_type.toUpperCase()}`,
      event.event_type
    ),
    change: changeLine(event),
    isNote: event.event_type === TICKET_NOTE_EVENT_TYPE,
    // Nil for an event the system wrote: the SLA sweeper, or a case opened by an operational signal.
    actor: event.user_name || t('SUPPORT_TICKETS.DETAIL.HISTORY.SYSTEM'),
  }))
);

const isNoteEmpty = computed(() => !note.value.trim());

const submitNote = () => {
  if (isNoteEmpty.value) return;
  emit('addNote', note.value.trim());
  note.value = '';
};
</script>

<template>
  <section class="flex flex-col gap-4">
    <h2 class="m-0 text-heading-2 text-n-slate-12">
      {{ t('SUPPORT_TICKETS.DETAIL.HISTORY.TITLE') }}
    </h2>

    <div
      v-if="isLoading && !entries.length"
      class="flex items-center justify-center py-10 text-n-slate-11"
    >
      <Spinner />
    </div>

    <p
      v-else-if="!entries.length"
      class="py-6 m-0 text-center text-body-main text-n-slate-11"
    >
      {{ t('SUPPORT_TICKETS.DETAIL.HISTORY.EMPTY') }}
    </p>

    <template v-else>
      <Button
        v-if="hasMore"
        :label="t('SUPPORT_TICKETS.DETAIL.HISTORY.LOAD_MORE')"
        variant="faded"
        color="slate"
        size="sm"
        :is-loading="isLoading"
        @click="emit('loadMore')"
      />

      <ul class="flex flex-col m-0 list-none divide-y divide-n-weak">
        <li v-for="entry in entries" :key="entry.id" class="flex gap-3 py-3">
          <span
            class="mt-0.5 shrink-0 size-4 text-n-slate-10"
            :class="entry.icon"
            aria-hidden="true"
          />
          <div class="flex flex-col gap-1 min-w-0 grow">
            <div class="flex items-baseline justify-between gap-2">
              <span class="text-heading-3 text-n-slate-12">
                {{ entry.title }}
              </span>
              <time
                :title="
                  messageTimestamp(entry.created_at, 'MMM d, yyyy h:mm a')
                "
                class="shrink-0 tabular-nums text-label-small text-n-slate-10"
              >
                {{ dynamicTime(entry.created_at) }}
              </time>
            </div>
            <p v-if="entry.change" class="m-0 text-body-main text-n-slate-11">
              {{ entry.change }}
            </p>
            <p
              v-if="entry.isNote && entry.body"
              class="p-3 m-0 whitespace-pre-line break-words rounded-lg bg-n-alpha-1 text-body-main text-n-slate-12"
            >
              {{ entry.body }}
            </p>
            <span class="text-label-small text-n-slate-10">
              {{ entry.actor }}
            </span>
          </div>
        </li>
      </ul>
    </template>

    <div v-if="canAddNote" class="flex flex-col gap-2">
      <TextArea
        v-model="note"
        :label="t('SUPPORT_TICKETS.DETAIL.NOTE.TITLE')"
        :placeholder="t('SUPPORT_TICKETS.DETAIL.NOTE.PLACEHOLDER')"
        :max-length="TICKET_NOTE_MAX_LENGTH"
        show-character-count
        auto-height
      />
      <Button
        class="self-end"
        :label="t('SUPPORT_TICKETS.DETAIL.NOTE.SUBMIT')"
        icon="i-lucide-sticky-note"
        size="sm"
        :disabled="isNoteEmpty || isSaving"
        :is-loading="isSaving"
        @click="submitNote"
      />
    </div>
  </section>
</template>
