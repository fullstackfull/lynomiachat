<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';
import CaptainGenerationDetails from '../CaptainGenerationDetails.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION, SENDER_TYPES } from '../constants';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const {
  variant,
  orientation,
  inReplyTo,
  shouldGroupWithNext,
  id,
  sender,
  senderType,
} = useMessageContext();
const { t } = useI18n();

const isCaptainMessage = computed(
  () =>
    (sender.value?.type ?? senderType.value) === SENDER_TYPES.CAPTAIN_ASSISTANT
);

const metaColorClass = computed(() =>
  variant.value === MESSAGE_VARIANTS.PRIVATE
    ? 'text-n-amber-12/50'
    : 'text-n-slate-11'
);

const emailMetaClass = computed(() =>
  variant.value === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : ''
);

// THE TEAM'S OWN VOICE IS THE BRAND'S COLOUR, AND IT WAS THE RETIRED ONE'S.
//
// An agent's reply -- the thing an agent writes all day, and the most-drawn surface in the product -- was set
// on `--solid-blue` (218 236 255), a tint of the blue this installation retired when it became Lynomia, while
// the BOT and TEMPLATE variants below were already on the brand's own iris. The account's own replies spoke
// in the old identity and its automations spoke in the new one.
//
// `iris-5` rather than `solid-iris`: it is the brand hue one step stronger than the tint the automated
// variants carry, so the human reply still reads as distinct from the bot reply -- which is the distinction
// the blue/iris pair was carrying, at the same contrast, in the right colour. It stays a LIGHT field in both
// modes on purpose: `prose-bubble` (tailwind.config.js) hardcodes `--slate-12` for body text, headings,
// `strong` and links, so a saturated field would need every one of those overridden in every bubble type.
const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: 'bg-n-iris-5 text-n-slate-12',
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-solid-amber text-n-amber-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]: 'bg-n-slate-4 text-n-slate-12',
  [MESSAGE_VARIANTS.ACTIVITY]: 'bg-n-alpha-1 text-n-slate-11 text-sm',
  [MESSAGE_VARIANTS.BOT]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.TEMPLATE]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-xl ltr:rounded-bl-sm rtl:rounded-br-sm',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-xl ltr:rounded-br-sm rtl:rounded-bl-sm',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
  } else {
    classToApply.push('rounded-lg');
  }

  return classToApply;
});

const scrollToMessage = () => {
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: inReplyTo.value.id,
  });
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    !shouldGroupWithNext.value &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);

const replyToPreview = computed(() => {
  if (!inReplyTo) return '';

  const { content, attachments } = inReplyTo.value;

  if (content) return new MessageFormatter(content).formattedMessage;
  if (attachments?.length) {
    const firstAttachment = attachments[0];
    const fileType = firstAttachment.fileType ?? firstAttachment.file_type;

    return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);
  }

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});
</script>

<template>
  <div
    class="text-sm min-w-0"
    :class="[
      messageClass,
      {
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <div
      v-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-lg cursor-pointer bg-n-alpha-black1"
      @click="scrollToMessage"
    >
      <div
        v-dompurify-html="replyToPreview"
        class="prose prose-bubble line-clamp-2"
      />
    </div>
    <slot />
    <template v-if="shouldShowMeta">
      <CaptainGenerationDetails
        v-if="isCaptainMessage"
        :message-id="id"
        class="mt-2"
      >
        <template #meta>
          <MessageMeta :class="[emailMetaClass, metaColorClass]" />
        </template>
      </CaptainGenerationDetails>
      <MessageMeta
        v-else
        :class="[flexOrientationClass, emailMetaClass, metaColorClass]"
        class="mt-2"
      />
    </template>
  </div>
</template>
