<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import { CALL_KIND } from './constants';

const props = defineProps({
  kind: {
    type: String,
    required: true,
  },
});

const { t } = useI18n();

// The call's own vocabulary, mapped to the shared tones. This component stays the only place that
// knows about CALL_KIND; what it no longer knows is which colour each state is painted.
const KIND_CONFIG = {
  [CALL_KIND.ONGOING]: { icon: 'i-lucide-phone-call', tone: 'success' },
  [CALL_KIND.INCOMING]: { icon: 'i-lucide-phone-incoming', tone: 'neutral' },
  [CALL_KIND.OUTGOING]: { icon: 'i-lucide-phone-outgoing', tone: 'neutral' },
  [CALL_KIND.MISSED]: { icon: 'i-lucide-phone-missed', tone: 'danger' },
  [CALL_KIND.NO_REPLY]: { icon: 'i-lucide-phone-outgoing', tone: 'warning' },
  [CALL_KIND.FAILED]: { icon: 'i-lucide-phone-off', tone: 'danger' },
};

const config = computed(() => KIND_CONFIG[props.kind]);
</script>

<template>
  <!-- `w-20` and `justify-center` are the call list's own: every row's badge is the same width so the
       column reads as a column. That is this component's job, not the badge system's. -->
  <Label
    compact
    variant="solid"
    :tone="config.tone"
    :label="t(`CALLS_PAGE.STATUS.${kind.toUpperCase()}`)"
    class="justify-center w-20 px-1"
  >
    <template #icon>
      <Icon :icon="config.icon" class="size-3 flex-shrink-0" />
    </template>
  </Label>
</template>
