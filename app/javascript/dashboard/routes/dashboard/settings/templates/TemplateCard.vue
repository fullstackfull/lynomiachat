<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import {
  formatTemplateLabel,
  formatTemplateLanguage,
  templateStatusLabelKey,
  templateStatusTone,
  templateTypeKey,
} from './templateUtils';

const props = defineProps({
  template: {
    type: Object,
    required: true,
  },
});
const emit = defineEmits(['preview', 'action']);
// What each action looks like in the menu. The list itself comes from the server, which derives it from WhatsApp's
// current rules, so a control is never shown for something the API would refuse
// (custom/app/services/whatsapp/templates/actions.rb).
const ACTION_ICONS = {
  submit: 'i-lucide-send',
  edit: 'i-lucide-pencil',
  duplicate: 'i-lucide-copy',
  delete: 'i-lucide-trash-2',
};
const MENU_ACTIONS = ['submit', 'edit', 'duplicate', 'delete'];

const { t } = useI18n();

const isMenuOpen = ref(false);

const showStatus = computed(
  () => props.template.status?.toLowerCase() !== 'approved'
);
const statusLabel = computed(() => {
  const key = templateStatusLabelKey(props.template.status);

  return key ? t(key) : formatTemplateLabel(props.template.status);
});

const menuItems = computed(() =>
  MENU_ACTIONS.filter(action =>
    (props.template.allowed_actions || []).includes(action)
  ).map(action => ({
    label: t(`WHATSAPP_TEMPLATE_MGMT.ACTIONS.${action.toUpperCase()}`),
    value: action,
    action,
    icon: ACTION_ICONS[action],
  }))
);

const handleAction = ({ action }) => {
  isMenuOpen.value = false;
  emit('action', action);
};
</script>

<template>
  <div
    class="flex items-center justify-between gap-4 py-4 cursor-pointer group"
    role="button"
    tabindex="0"
    data-test-id="template-row"
    @click="emit('preview')"
    @keydown.enter="emit('preview')"
    @keydown.space.prevent="emit('preview')"
  >
    <div class="flex items-center min-w-0 gap-3">
      <span
        class="grid border rounded-xl shadow-sm size-10 shrink-0 place-items-center bg-n-alpha-3 border-n-strong ring ring-n-solid-1"
      >
        <ChannelIcon
          :inbox="template.inboxes[0]"
          class="size-5 text-n-slate-11"
        />
      </span>
      <div class="flex flex-col min-w-0 gap-1">
        <div class="flex items-center min-w-0 gap-2">
          <span class="truncate text-heading-3 text-n-slate-12">
            {{ template.name }}
          </span>
          <Label
            v-if="showStatus"
            compact
            :label="statusLabel"
            :tone="templateStatusTone(template.status).tone"
            :variant="templateStatusTone(template.status).variant"
          />
        </div>
        <div
          class="flex flex-wrap items-center gap-2 text-body-main text-n-slate-11"
        >
          <span>
            {{
              $t(`WHATSAPP_TEMPLATE_MGMT.TYPES.${templateTypeKey(template)}`)
            }}
          </span>
          <div class="w-px h-3 rounded-lg bg-n-strong" />
          <span>{{ formatTemplateLanguage(template.language) }}</span>
          <div class="w-px h-3 rounded-lg bg-n-strong" />
          <span class="truncate">{{ template.inboxNames }}</span>
        </div>
      </div>
    </div>
    <div class="flex items-center gap-1 shrink-0">
      <Button
        v-tooltip.top="$t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.TITLE')"
        icon="i-lucide-eye"
        color="slate"
        size="sm"
        :aria-label="
          $t('WHATSAPP_TEMPLATE_MGMT.PREVIEW.OPEN', { name: template.name })
        "
        @click.stop="emit('preview')"
      />
      <div
        v-if="menuItems.length"
        v-on-click-outside="() => (isMenuOpen = false)"
        class="relative"
        data-test-id="template-actions"
        @click.stop
      >
        <Button
          icon="i-lucide-ellipsis-vertical"
          color="slate"
          size="sm"
          aria-haspopup="menu"
          :aria-expanded="isMenuOpen"
          :aria-label="
            $t('WHATSAPP_TEMPLATE_MGMT.ACTIONS.MORE', { name: template.name })
          "
          @click.stop="isMenuOpen = !isMenuOpen"
        />
        <DropdownMenu
          v-if="isMenuOpen"
          :menu-items="menuItems"
          class="mt-2 min-w-44 top-full end-0"
          @action="handleAction"
        />
      </div>
    </div>
  </div>
</template>
