import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import ArticleEditor from './ArticleEditor.vue';

const labels = {
  heading2: 'Heading',
  heading3: 'Subheading',
  bold: 'Bold',
  italic: 'Italic',
  inlineCode: 'Code',
  bulletList: 'Bulleted list',
  orderedList: 'Numbered list',
  blockquote: 'Quote',
  codeBlock: 'Code block',
  table: 'Table',
  link: 'Link',
  insertImage: 'Insert image',
  replaceImage: 'Replace image',
  replacedImage: 'Replaced',
  noImageAtCaret: 'Put the cursor on an image first.',
  uploading: 'Uploading',
  showPreview: 'Show preview',
  hidePreview: 'Hide preview',
  previewTitle: 'Preview',
  previewUpdating: 'Updating preview',
  altRequired: 'Describe this image.',
  altHint: 'It is read aloud and it appears in search results.',
  altConfirm: 'Insert',
  altCancel: 'Cancel',
  missingAlt: 'An image has no alt text.',
  dataImageFound: 'An image is pasted in as data.',
  blockedSubmit: 'Fix the problems above.',
  unsupportedType: 'That file type cannot be published.',
  choosePortalFirst: 'Choose the portal first.',
  dataImageRefused: 'That image was pasted in as data.',
};

const componentData = (overrides = {}) => ({
  content: '',
  locale: 'en',
  fieldName: 'article[content]',
  fieldId: 'article_content',
  portalFieldName: 'article[portal_id]',
  previewEndpoint: '/super_admin/articles/preview_markdown',
  mediaEndpoint: '/super_admin/documentation_media',
  labels,
  ...overrides,
});

// The editor is mounted inside Administrate's form, and it reaches out to that form for the portal select and
// the submit event. So the spec mounts it in one.
const mountInForm = (overrides = {}) => {
  const form = document.createElement('form');
  form.innerHTML =
    '<select name="article[portal_id]"><option value="7">Docs</option></select>';
  document.body.appendChild(form);
  const host = document.createElement('div');
  form.appendChild(host);

  const wrapper = mount(ArticleEditor, {
    props: { componentData: componentData(overrides) },
    attachTo: host,
  });
  return { wrapper, form };
};

const MEDIA_ENDPOINT = '/super_admin/documentation_media';
const PREVIEW_ENDPOINT = '/super_admin/articles/preview_markdown';

// The editor previews on mount, so a single blanket mock would conflate the preview request with the media
// request. This routes by URL and lets each assertion look only at the calls it means.
const mockFetch = (mediaResponse = null) =>
  vi.fn().mockImplementation(url => {
    if (url.startsWith(MEDIA_ENDPOINT)) return Promise.resolve(mediaResponse);
    return Promise.resolve({ ok: true, text: async () => '<p>rendered</p>' });
  });

// The upload is async, so the component's state settles a macrotask after the click, not a tick.
const flush = async () => {
  await new Promise(resolve => {
    setTimeout(resolve, 0);
  });
  await nextTick();
};

const mediaCalls = () =>
  global.fetch.mock.calls.filter(([url]) => url.startsWith(MEDIA_ENDPOINT));

describe('ArticleEditor', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
    global.fetch = mockFetch();
  });

  it('renders the textarea the Administrate form posts, not a second field', () => {
    const { wrapper } = mountInForm({ content: '# Title' });
    const textarea = wrapper.get('textarea');

    expect(textarea.attributes('name')).toBe('article[content]');
    expect(textarea.attributes('id')).toBe('article_content');
    expect(textarea.element.value).toBe('# Title');
  });

  // The corpus is half Arabic and there is no server-side direction source (see RTL_LOCALES in the component).
  it('sets the direction from the article locale', () => {
    expect(
      mountInForm({ locale: 'en' }).wrapper.get('textarea').attributes('dir')
    ).toBe('ltr');
    expect(
      mountInForm({ locale: 'ar' }).wrapper.get('textarea').attributes('dir')
    ).toBe('rtl');
  });

  it('applies a toolbar command to the source', async () => {
    const { wrapper } = mountInForm({ content: 'A title' });
    const textarea = wrapper.get('textarea');
    textarea.element.setSelectionRange(0, 0);

    await wrapper
      .findAll('button')
      .find(b => b.text() === 'Heading')
      .trigger('click');

    expect(textarea.element.value).toBe('## A title');
  });

  describe('publication blockers', () => {
    it('names the line of an image with no alt text and blocks the save', async () => {
      const { wrapper, form } = mountInForm({
        content: 'intro\n\n![](media:a/b.png)',
      });
      await nextTick();

      expect(wrapper.text()).toContain(labels.missingAlt);

      const submit = new Event('submit', { cancelable: true });
      form.dispatchEvent(submit);

      expect(submit.defaultPrevented).toBe(true);
      await nextTick();
      expect(wrapper.text()).toContain(labels.blockedSubmit);
    });

    it('lets a save through when every image is described', async () => {
      const { wrapper, form } = mountInForm({
        content: '![Step two](media:a/b.png)',
      });
      await nextTick();

      expect(wrapper.text()).not.toContain(labels.missingAlt);

      const submit = new Event('submit', { cancelable: true });
      form.dispatchEvent(submit);

      expect(submit.defaultPrevented).toBe(false);
    });

    it('blocks a data: image, which cannot be published', async () => {
      const { wrapper } = mountInForm({
        content: '![x](data:image/png;base64,AA)',
      });
      await nextTick();

      expect(wrapper.text()).toContain(labels.dataImageFound);
    });
  });

  describe('media', () => {
    const uploadResponse = {
      ok: true,
      json: async () => ({
        key: 'uploads/8f3a1c2b5d7e9a04-step-two.png',
        markdown: '![Step two](media:uploads/8f3a1c2b5d7e9a04-step-two.png)',
        width: 1280,
        height: 720,
      }),
    };

    // Alt text first, because Documentation::MediaUpload#create! takes it and refuses a blank one: the editor
    // cannot upload without one, so it cannot insert an undescribed image either.
    it('asks for alt text before it uploads anything', async () => {
      global.fetch = mockFetch(uploadResponse);
      const { wrapper } = mountInForm();
      const file = new File(['bytes'], 'step-2.png', { type: 'image/png' });

      await wrapper.get('textarea').trigger('paste', {
        clipboardData: { files: [file], getData: () => '' },
      });
      await nextTick();

      expect(wrapper.text()).toContain(labels.altRequired);
      expect(mediaCalls()).toHaveLength(0);
      expect(wrapper.get('textarea').element.value).toBe('');
    });

    it('sends the alt with the bytes and inserts the markdown the server composed', async () => {
      global.fetch = mockFetch(uploadResponse);
      const { wrapper } = mountInForm();
      const file = new File(['bytes'], 'step-2.png', { type: 'image/png' });

      await wrapper.get('textarea').trigger('paste', {
        clipboardData: { files: [file], getData: () => '' },
      });
      await nextTick();
      await wrapper.get('[data-testid="alt-input"]').setValue('Step two');
      await wrapper.get('[data-testid="alt-confirm"]').trigger('click');
      await flush();

      const [url, options] = mediaCalls().at(-1);
      expect(url).toBe(MEDIA_ENDPOINT);
      expect(options.method).toBe('POST');
      expect(options.body.get('alt')).toBe('Step two');
      expect(options.body.get('portal_id')).toBe('7');
      // Verbatim: the editor composes no media: string of its own.
      expect(wrapper.get('textarea').element.value).toBe(
        '![Step two](media:uploads/8f3a1c2b5d7e9a04-step-two.png)'
      );
    });

    it('shows the server refusal rather than inserting anything', async () => {
      global.fetch = mockFetch({
        ok: false,
        statusText: 'Unprocessable Entity',
        json: async () => ({ error: 'image/svg+xml is not permitted.' }),
      });
      const { wrapper } = mountInForm();
      const file = new File(['bytes'], 'a.png', { type: 'image/png' });

      await wrapper
        .get('textarea')
        .trigger('drop', { dataTransfer: { files: [file] } });
      await nextTick();
      await wrapper.get('[data-testid="alt-input"]').setValue('Alt');
      await wrapper.get('[data-testid="alt-confirm"]').trigger('click');
      await flush();

      expect(wrapper.text()).toContain('image/svg+xml is not permitted.');
      expect(wrapper.get('textarea').element.value).toBe('');
    });

    it('refuses a data: image pasted as text rather than storing it', async () => {
      const { wrapper } = mountInForm();

      await wrapper.get('textarea').trigger('paste', {
        clipboardData: {
          files: [],
          getData: () => 'data:image/png;base64,AAAA',
        },
      });
      await nextTick();

      expect(wrapper.text()).toContain(labels.dataImageRefused);
      expect(mediaCalls()).toHaveLength(0);
    });

    it('refuses a file type that cannot be published, before asking for alt text', async () => {
      const { wrapper } = mountInForm();
      const file = new File(['<svg/>'], 'd.svg', { type: 'image/svg+xml' });

      await wrapper
        .get('textarea')
        .trigger('drop', { dataTransfer: { files: [file] } });
      await nextTick();

      expect(wrapper.text()).toContain(labels.unsupportedType);
      expect(wrapper.text()).not.toContain(labels.altRequired);
    });

    it('tells the operator when no portal is chosen yet, since the namespace is per-portal', async () => {
      const form = document.createElement('form');
      form.innerHTML =
        '<select name="article[portal_id]"><option value="">None</option></select>';
      document.body.appendChild(form);
      const host = document.createElement('div');
      form.appendChild(host);
      const wrapper = mount(ArticleEditor, {
        props: { componentData: componentData() },
        attachTo: host,
      });

      await wrapper.get('textarea').trigger('drop', {
        dataTransfer: {
          files: [new File(['b'], 'a.png', { type: 'image/png' })],
        },
      });
      await nextTick();

      expect(wrapper.text()).toContain(labels.choosePortalFirst);
    });
  });

  it('asks the server to render the preview rather than rendering Markdown in the browser', async () => {
    mountInForm({ content: '## Heading' });
    await nextTick();

    expect(global.fetch).toHaveBeenCalledWith(
      PREVIEW_ENDPOINT,
      expect.objectContaining({ method: 'POST' })
    );
  });
});
