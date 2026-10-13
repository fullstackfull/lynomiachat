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

  // THE REGRESSION THESE EXAMPLES EXIST TO PREVENT.
  //
  // An earlier version of this component gated the WhatsApp tile on the Meta embedded-signup credentials
  // (whatsappAppId, whatsappConfigurationId), by analogy with facebook/instagram/tiktok. That analogy is
  // wrong, and it shipped. The tile does not open an embedded signup; it opens a PROVIDER SELECTION page
  // (settings/inbox/channels/Whatsapp.vue:98-125) whose list is WhatsApp Cloud (whose description switches to
  // manual setup when embedded signup is unavailable), Twilio, and -- only when `canUseEmbeddedSignup` --
  // the Meta embedded-signup option. Two of the three never touch the Meta credentials, and the page already
  // removes the one that does. So gating the tile left an installation running Twilio or manual Cloud API
  // with no route to a WhatsApp inbox at all.
  //
  // The real "cannot complete" guard is in the composable: useWhatsappEmbeddedSignup refuses before loading
  // the SDK and surfaces a named error, rather than sending config_id: undefined to Meta.
  describe('whatsapp', () => {
    it('is available with the Meta credentials present', () => {
      expect(isDisabled(mountTile('whatsapp'))).toBe(false);
    });

    it.each([
      [
        'the configuration id is missing',
        c => delete c.whatsappConfigurationId,
      ],
      [
        'the configuration id is blank',
        c => {
          c.whatsappConfigurationId = '';
        },
      ],
      ['the app id is missing', c => delete c.whatsappAppId],
      [
        "the app id is the 'none' sentinel",
        c => {
          c.whatsappAppId = 'none';
        },
      ],
      [
        'there is no installation config at all',
        () => {
          window.chatwootConfig = {};
        },
      ],
    ])(
      'stays available when %s, because Twilio and manual Cloud API do not need it',
      (_label, mutate) => {
        mutate(window.chatwootConfig);

        expect(isDisabled(mountTile('whatsapp'))).toBe(false);
      }
    );
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
