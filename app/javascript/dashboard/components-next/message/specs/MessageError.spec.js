import { mount } from '@vue/test-utils';
import { computed } from 'vue';
import MessageError from '../MessageError.vue';
import { MESSAGE_STATUS, ORIENTATION } from '../constants';

const messageContext = {
  orientation: computed(() => ORIENTATION.RIGHT),
  status: computed(() => MESSAGE_STATUS.FAILED),
  createdAt: computed(() => Math.floor(Date.now() / 1000)),
  content: computed(() => 'hello'),
  attachments: computed(() => []),
};

let documentationUrl;
let docsLinkKey;

vi.mock('../provider.js', () => ({
  useMessageContext: () => messageContext,
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({
    docsLink: key => {
      docsLinkKey = key;
      return documentationUrl;
    },
  }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));

const RECIPIENT_RESTRICTED = {
  code: 131049,
  classification: 'META_RECIPIENT_DELIVERY_RESTRICTION',
  recipientScoped: true,
};

const BILLING = {
  code: 131042,
  classification: 'META_BILLING_ELIGIBILITY',
  recipientScoped: false,
};

const mountError = props =>
  mount(MessageError, {
    props: { error: '131049: Not delivered', ...props },
    global: {
      stubs: { Icon: { template: '<i />' } },
      directives: { tooltip: {} },
    },
  });

const retryButton = wrapper =>
  wrapper.find('button[aria-label="CHAT_LIST.DELIVERY_FAILURE.RETRY"]');

beforeEach(() => {
  documentationUrl = 'https://docs.example.com/whatsapp-troubleshooting';
  docsLinkKey = undefined;
  messageContext.createdAt = computed(() => Math.floor(Date.now() / 1000));
  messageContext.status = computed(() => MESSAGE_STATUS.FAILED);
  messageContext.content = computed(() => 'hello');
  messageContext.attachments = computed(() => []);
});

describe('MessageError', () => {
  // The whole point: an agent reading "131049: ..." could not tell whether to try again, whether the number was
  // broken, or whether the customer was at fault.
  it('explains a classified refusal in words, without a hover', () => {
    const wrapper = mountError({ deliveryFailure: RECIPIENT_RESTRICTED });

    expect(wrapper.text()).toContain(
      'CHAT_LIST.DELIVERY_FAILURE.META_RECIPIENT_DELIVERY_RESTRICTION.TITLE'
    );
    expect(wrapper.text()).toContain(
      'CHAT_LIST.DELIVERY_FAILURE.META_RECIPIENT_DELIVERY_RESTRICTION.BODY'
    );
  });

  it("keeps the provider's own words, which an operator quotes back to Meta", () => {
    const wrapper = mountError({ deliveryFailure: RECIPIENT_RESTRICTED });

    expect(wrapper.text()).toContain('131049: Not delivered');
    expect(wrapper.text()).toContain(
      'CHAT_LIST.DELIVERY_FAILURE.PROVIDER_RESPONSE_LABEL'
    );
  });

  // The refusal is the provider's English inside a paragraph that may be Arabic, where its leading error code
  // was being reordered to the end of the line.
  it('isolates the provider text from the direction of the sentence around it', () => {
    const bdi = mountError({ deliveryFailure: RECIPIENT_RESTRICTED }).find(
      'bdi'
    );

    expect(bdi.attributes('dir')).toBe('auto');
    expect(bdi.text()).toBe('131049: Not delivered');
  });

  // Re-sending would be refused the same way and each attempt is another quality signal against the number, so
  // Retry is withdrawn rather than left to fail. The retry endpoint refuses it too.
  it('withdraws Retry for a recipient-scoped refusal and says why', () => {
    const wrapper = mountError({ deliveryFailure: RECIPIENT_RESTRICTED });

    expect(retryButton(wrapper).exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'CHAT_LIST.DELIVERY_FAILURE.NO_RETRY_REASON'
    );
  });

  // 131042 is billing: an administrator fixes it outside Lynomia and the same message then sends, so its retry
  // stays. This is why the UI keys on recipient scope rather than on "do not auto retry".
  it('keeps Retry for a billing refusal the operator can actually fix', () => {
    const wrapper = mountError({ deliveryFailure: BILLING });

    expect(retryButton(wrapper).exists()).toBe(true);
    expect(wrapper.text()).not.toContain(
      'CHAT_LIST.DELIVERY_FAILURE.NO_RETRY_REASON'
    );
  });

  it('emits retry when the button is pressed', async () => {
    const wrapper = mountError({ deliveryFailure: BILLING });

    await retryButton(wrapper).trigger('click');

    expect(wrapper.emitted('retry')).toHaveLength(1);
  });

  // Every other failure -- an unclassified WhatsApp code, a Twilio rejection, an SMTP bounce -- keeps the
  // behaviour it has always had: the provider's text and a retry, with nothing invented about it.
  it('shows the raw error and a retry when the refusal is not classified', () => {
    const wrapper = mountError({ deliveryFailure: null });

    expect(wrapper.find('bdi').text()).toBe('131049: Not delivered');
    expect(wrapper.text()).not.toContain(
      'CHAT_LIST.DELIVERY_FAILURE.PROVIDER_RESPONSE_LABEL'
    );
    expect(wrapper.text()).not.toContain('META_RECIPIENT_DELIVERY_RESTRICTION');
    expect(retryButton(wrapper).exists()).toBe(true);
  });

  it('offers no documentation link for an unclassified refusal', () => {
    expect(mountError({ deliveryFailure: null }).find('a').exists()).toBe(
      false
    );
  });

  it('links to the troubleshooting article for a classified refusal', () => {
    const link = mountError({ deliveryFailure: BILLING }).find('a');

    expect(link.attributes('href')).toBe(documentationUrl);
    expect(link.attributes('rel')).toBe('noopener noreferrer');
  });

  // A branded installation that configured no documentation URL gets no link, which is how every other product
  // link already behaves.
  it('renders no link when the installation has no documentation', () => {
    documentationUrl = '';

    expect(mountError({ deliveryFailure: BILLING }).find('a').exists()).toBe(
      false
    );
  });

  it('still withholds Retry for a message older than a day', () => {
    messageContext.createdAt = computed(
      () => Math.floor(Date.now() / 1000) - 60 * 60 * 25
    );

    expect(retryButton(mountError({ deliveryFailure: BILLING })).exists()).toBe(
      false
    );
  });

  // An agent reading "131049" wants the page about 131049. Each classified code has its own article, and a code
  // with no article falls back to the general one rather than linking somewhere that does not answer the question.
  describe('the Learn more destination', () => {
    it('asks for the article about this code', () => {
      mountError({ deliveryFailure: RECIPIENT_RESTRICTED });
      expect(docsLinkKey).toBe('whatsappError131049');

      mountError({ deliveryFailure: BILLING });
      expect(docsLinkKey).toBe('whatsappError131042');
    });

    it('falls back to the general article for a code with no page of its own', () => {
      mountError({
        deliveryFailure: { code: 133010, classification: 'UNCLASSIFIED' },
      });

      expect(docsLinkKey).toBe('whatsappTroubleshooting');
    });

    it('renders no link at all when the installation has no documentation', () => {
      documentationUrl = '';

      expect(
        mountError({ deliveryFailure: RECIPIENT_RESTRICTED }).find('a').exists()
      ).toBe(false);
    });
  });

  // The parent places this block against its bubble with a `justify-*` class on the row, so the column inside has
  // to carry the cross-axis alignment itself -- while its sentences stay start-aligned, because ragged-left body
  // copy beside an outgoing bubble is markedly harder to read.
  it('aligns with the bubble it belongs to, and keeps its sentences readable', () => {
    const right = mountError({ deliveryFailure: null }).find('.flex-col');
    expect(right.classes()).toContain('items-end');
    expect(right.classes()).toContain('text-start');
    expect(right.classes()).not.toContain('text-end');

    messageContext.orientation = computed(() => ORIENTATION.LEFT);
    expect(
      mountError({ deliveryFailure: null }).find('.flex-col').classes()
    ).toContain('items-start');
    messageContext.orientation = computed(() => ORIENTATION.RIGHT);
  });
});
