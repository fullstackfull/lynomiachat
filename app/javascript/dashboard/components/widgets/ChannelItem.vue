<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import ChannelSelector from '../ChannelSelector.vue';

const props = defineProps({
  channel: {
    type: Object,
    required: true,
  },
  enabledFeatures: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['channelItemClick']);
const { isOnChatwootCloud } = useAccount();

const hasFbConfigured = computed(() => {
  return window.chatwootConfig?.fbAppId;
});

const hasInstagramConfigured = computed(() => {
  return window.chatwootConfig?.instagramAppId;
});

const hasTiktokConfigured = computed(() => {
  return window.chatwootConfig?.tiktokAppId;
});

// WhatsApp is onboarded only through Meta embedded signup, which needs the app id and the signup
// configuration id, and treats the 'none' sentinel as absent -- the same three conditions
// onboarding/inbox-setup/useChannelConfig.js:22-29 already applies. Without this the tile was the one
// OAuth/SDK provider offered unconditionally, so a workspace on an installation with no WhatsApp
// configuration could click through to a signup that cannot complete.
const hasWhatsappConfigured = computed(() => {
  const config = window.chatwootConfig ?? {};
  return (
    Boolean(config.whatsappAppId) &&
    config.whatsappAppId !== 'none' &&
    Boolean(config.whatsappConfigurationId)
  );
});

const isActive = computed(() => {
  const { key } = props.channel;
  if (Object.keys(props.enabledFeatures).length === 0) {
    return false;
  }
  if (key === 'website') {
    return props.enabledFeatures.channel_website;
  }
  if (key === 'facebook') {
    return props.enabledFeatures.channel_facebook && hasFbConfigured.value;
  }
  if (key === 'email') {
    return props.enabledFeatures.channel_email;
  }

  if (key === 'instagram') {
    return (
      props.enabledFeatures.channel_instagram && hasInstagramConfigured.value
    );
  }

  if (key === 'tiktok') {
    return props.enabledFeatures.channel_tiktok && hasTiktokConfigured.value;
  }

  if (key === 'voice' || key === 'whatsapp_call') {
    return props.enabledFeatures.channel_voice;
  }

  // Rendered disabled rather than hidden when unconfigured, which is what this component already does for
  // facebook, instagram and tiktok -- the template binds `:disabled="!isActive && !canRequestTiktokAccess"`.
  if (key === 'whatsapp') {
    return hasWhatsappConfigured.value;
  }

  return [
    'website',
    'twilio',
    'api',
    'sms',
    'telegram',
    'line',
    'instagram',
    'tiktok',
    'voice',
  ].includes(key);
});

const isComingSoon = computed(() => {
  const { key } = props.channel;
  // Show "Coming Soon" only if the channel is marked as coming soon
  // and the corresponding feature flag is not enabled yet.
  return ['voice'].includes(key) && !isActive.value;
});

const isBeta = computed(() => {
  return ['tiktok', 'voice', 'whatsapp_call'].includes(props.channel.key);
});

const canRequestTiktokAccess = computed(() => {
  return (
    props.channel.key === 'tiktok' &&
    isOnChatwootCloud.value &&
    hasTiktokConfigured.value &&
    Object.keys(props.enabledFeatures).length > 0 &&
    !props.enabledFeatures.channel_tiktok
  );
});

const hasVoiceBadge = computed(() => {
  return (
    ['voice', 'whatsapp_call'].includes(props.channel.key) &&
    !!props.enabledFeatures.channel_voice
  );
});

const onItemClick = () => {
  if (canRequestTiktokAccess.value) {
    window.$chatwoot?.toggle();
    return;
  }

  if (isActive.value) {
    emit('channelItemClick', props.channel.key);
  }
};
</script>

<template>
  <ChannelSelector
    :title="channel.title"
    :description="channel.description"
    :icon="channel.icon"
    :is-coming-soon="isComingSoon"
    :is-beta="isBeta"
    :has-voice-badge="hasVoiceBadge"
    :disabled="!isActive && !canRequestTiktokAccess"
    @click="onItemClick"
  />
</template>
