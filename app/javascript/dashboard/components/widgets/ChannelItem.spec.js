import { mount } from '@vue/test-utils';
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import ChannelItem from './ChannelItem.vue';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isOnChatwootCloud: { value: false } }),
}));

// The tile's only observable output is the `disabled` prop it hands ChannelSelector, which is
// `!isActive && !canRequestTiktokAccess` -- so asserting that prop IS asserting availability.
const ChannelSelectorStub = {
  name: 'ChannelSelector',
  props: [
    'title',
    'description',
    'icon',
    'isComingSoon',
    'isBeta',
    'hasVoiceBadge',
    'disabled',
  ],
  template: '<button :disabled="disabled">{{ title }}</button>',
};

const ALL_FEATURES = {
  channel_website: true,
  channel_facebook: true,
  channel_email: true,
  channel_instagram: true,
  channel_tiktok: true,
  channel_voice: true,
};

const mountTile = key =>
  mount(ChannelItem, {
    props: {
      channel: { key, title: key, description: '', icon: '' },
      enabledFeatures: ALL_FEATURES,
    },
    global: { stubs: { ChannelSelector: ChannelSelectorStub } },
    globalProperties: {},
  });

const isDisabled = wrapper =>
  wrapper.findComponent(ChannelSelectorStub).props('disabled');

describe('ChannelItem availability', () => {
  let originalConfig;

  beforeEach(() => {
    originalConfig = window.chatwootConfig;
    window.chatwootConfig = {
      fbAppId: 'fb',
      instagramAppId: 'ig',
      tiktokAppId: 'tt',
      whatsappAppId: 'wa-app',
      whatsappConfigurationId: 'wa-config',
    };
  });

  afterEach(() => {
    window.chatwootConfig = originalConfig;
  });

  // WhatsApp was the one OAuth/SDK provider offered unconditionally: it sat in the fallback `includes(key)`
  // list while facebook, instagram and tiktok each checked their installation credential. A workspace on an
  // installation with no WhatsApp configuration could click through to a signup that cannot complete.
  describe('whatsapp', () => {
    it('is available when both the app id and the configuration id are present', () => {
      expect(isDisabled(mountTile('whatsapp'))).toBe(false);
    });

    it('is unavailable when the configuration id is missing', () => {
      delete window.chatwootConfig.whatsappConfigurationId;

      expect(isDisabled(mountTile('whatsapp'))).toBe(true);
    });

    it('is unavailable when the configuration id is blank', () => {
      window.chatwootConfig.whatsappConfigurationId = '';

      expect(isDisabled(mountTile('whatsapp'))).toBe(true);
    });

    it('is unavailable when the app id is missing', () => {
      delete window.chatwootConfig.whatsappAppId;

      expect(isDisabled(mountTile('whatsapp'))).toBe(true);
    });

    // The sentinel an installation uses for "no Meta app"; useChannelConfig reads it the same way.
    it("is unavailable when the app id is the 'none' sentinel", () => {
      window.chatwootConfig.whatsappAppId = 'none';

      expect(isDisabled(mountTile('whatsapp'))).toBe(true);
    });

    // Disabled rather than hidden: the component renders the tile either way and binds `disabled`, which is
    // the pattern it already uses for the other three providers.
    it('still renders the tile when unavailable, rather than hiding it', () => {
      delete window.chatwootConfig.whatsappConfigurationId;
      const wrapper = mountTile('whatsapp');

      expect(wrapper.findComponent(ChannelSelectorStub).exists()).toBe(true);
    });
  });

  // Asserted so the whatsapp branch cannot have changed the providers around it.
  describe('the providers whose gating must not change', () => {
    it.each([
      ['facebook', 'fbAppId'],
      ['instagram', 'instagramAppId'],
      ['tiktok', 'tiktokAppId'],
    ])(
      '%s stays available with its credential and unavailable without it',
      (key, credential) => {
        expect(isDisabled(mountTile(key))).toBe(false);

        delete window.chatwootConfig[credential];
        expect(isDisabled(mountTile(key))).toBe(true);
      }
    );

    it('website needs no installation credential', () => {
      window.chatwootConfig = {};

      expect(isDisabled(mountTile('website'))).toBe(false);
    });
  });
});
