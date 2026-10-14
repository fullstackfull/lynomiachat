import { nextTick } from 'vue';

// THE OTHER HALF OF A TWO-HALF CONTRACT.
//
// `custom/app/views/super_admin/articles/_content_editor.html.erb:15` emits
// `data-component-name="DocumentationArticleEditor"`, and `documentation_editor_spec.rb:221` pins that string on
// the Rails side. The matching half is the `ComponentMapping` key in this entrypoint, and nothing pinned it: a
// one-character divergence between the two renders NOTHING -- `ComponentMapping[componentName]` is `undefined`,
// Vue mounts an empty component, the operator sees a blank editor -- while both sides' own tests stay green.
// `ArticleEditor.spec.js` mounts the component directly and so cannot see the registry at all.
//
// So this asserts the real path rather than comparing two strings: build the `#app` element exactly as
// `render_vue_component` does (app/controllers/super_admin/application_controller.rb:33-42) and check that the
// editor actually appears. The entrypoint registers its listener on import, and jsdom has already finished
// loading by then, so `DOMContentLoaded` is dispatched by hand.
describe('superadmin_pages entrypoint', () => {
  const props = {
    content: '# Audit logs',
    articleId: 7,
    locale: 'en',
    fieldName: 'article[content]',
    fieldId: 'article_content',
    portalFieldName: 'article[portal_id]',
    previewEndpoint: '/super_admin/articles/preview_markdown',
    mediaEndpoint: '/super_admin/documentation_media',
    labels: { showPreview: 'Show preview', hidePreview: 'Hide preview' },
  };

  const mountTarget = componentName => {
    document.body.innerHTML = '';
    const element = document.createElement('div');
    element.id = 'app';
    element.dataset.componentName = componentName;
    element.dataset.props = JSON.stringify(props);
    document.body.appendChild(element);
    return element;
  };

  beforeAll(async () => {
    await import('./superadmin_pages.js');
  });

  it('mounts the documentation editor for the name the Rails partial emits', async () => {
    mountTarget('DocumentationArticleEditor');

    document.dispatchEvent(new Event('DOMContentLoaded'));
    await nextTick();

    // The field the Administrate form posts, carrying the content the props supplied: proof the registry
    // resolved to the editor and the props reached it, not merely that something rendered.
    const field = document.querySelector('textarea[name="article[content]"]');
    expect(field).not.toBeNull();
    expect(field.value).toBe('# Audit logs');
  });

  // The discriminator for the example above: the same machinery with a name the registry does not hold renders
  // an empty mount point instead of throwing, which is exactly why a typo in either half is silent. Vue logs
  // `Invalid vnode type when creating vnode: undefined` and carries on; nothing reaches the operator.
  //
  // Measured: with the registry key changed to `DocumentationArticleEditorX`, the example above fails and this
  // one still passes -- so the pin is on the name matching, not merely on the editor existing.
  it('renders nothing for a name the registry does not hold', async () => {
    const element = mountTarget('DocumentationArticleEditorr');

    document.dispatchEvent(new Event('DOMContentLoaded'));
    await nextTick();

    expect(
      document.querySelector('textarea[name="article[content]"]')
    ).toBeNull();
    expect(element.textContent).toBe('');
  });
});
