<script>
import { defineComponent, h } from 'vue';
import Facebook from './channels/Facebook.vue';
import Website from './channels/Website.vue';
import Api from './channels/Api.vue';
import Email from './channels/Email.vue';
import Sms from './channels/Sms.vue';
import Whatsapp from './channels/Whatsapp.vue';
import Line from './channels/Line.vue';
import Telegram from './channels/Telegram.vue';
import Instagram from './channels/Instagram.vue';
import Tiktok from './channels/Tiktok.vue';

// Lynomia (docs/p11/00-p10-security-closure.md, SC5 and SC6). Three keys are deliberately absent, so
// /settings/inboxes/new/<key> renders nothing for them instead of a form that cannot work:
//
//   voice          offers a Twilio voice inbox for a channel type the server does not accept; submitting
//                  it 422s after asking for Twilio API key secrets it then discards.
//   whatsapp_call  creates a real WhatsApp inbox and then calls enable_whatsapp_calling, which has no route
//                  and no controller action; the 404 is reported to the operator as a Meta problem.
//   twitter        renders a working-looking "Sign in with Twitter" page for a channel whose connect entry
//                  point, locale key and gating flag were all removed, the flag by a migration that
//                  repurposed it. Nothing gates the URL itself.
//
// Nothing else is removed: the models, the tables, the Channels::Capability rows and every existing row stay
// exactly as they are, so no data is touched and Operations keeps reporting `unknown` rather than nothing.
const channelViewList = {
  facebook: Facebook,
  website: Website,
  api: Api,
  email: Email,
  sms: Sms,
  whatsapp: Whatsapp,
  line: Line,
  telegram: Telegram,
  instagram: Instagram,
  tiktok: Tiktok,
};

export default defineComponent({
  name: 'NewChannelView',
  props: {
    channelName: {
      type: String,
      required: true,
    },
  },
  render() {
    const ChannelComponent = channelViewList[this.channelName];
    return ChannelComponent ? h(ChannelComponent) : null;
  },
});
</script>
