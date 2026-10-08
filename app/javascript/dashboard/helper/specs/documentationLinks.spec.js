import {
  DOC_ARTICLES,
  documentationArticleUrl,
  whatsappErrorArticle,
} from '../documentationLinks';

describe('documentationArticleUrl', () => {
  it('builds an article address from a registry key', () => {
    expect(documentationArticleUrl('https://docs.example.com', 'labels')).toBe(
      'https://docs.example.com/labels'
    );
  });

  it('tolerates a trailing slash on the configured base', () => {
    expect(documentationArticleUrl('https://docs.example.com/', 'labels')).toBe(
      'https://docs.example.com/labels'
    );
  });

  it('returns no link when the installation has no documentation configured', () => {
    expect(documentationArticleUrl('', 'labels')).toBe('');
  });

  it('returns no link for a key the registry does not carry', () => {
    expect(
      documentationArticleUrl('https://docs.example.com', 'notAnArticle')
    ).toBe('');
  });
});

describe('whatsappErrorArticle', () => {
  // The codes the server classifies (custom/app/services/whatsapp/delivery_failure.rb) plus the ones the send
  // and receive paths name. Each has an article under custom/db/documentation/<locale>/whatsapp-errors/.
  it.each([
    [131049, 'whatsapp-error-131049'],
    [131042, 'whatsapp-error-131042'],
    [131053, 'whatsapp-error-131053'],
    [131060, 'whatsapp-error-131060'],
    [190, 'whatsapp-error-190'],
  ])('resolves %i to its own article', (code, slug) => {
    expect(DOC_ARTICLES[whatsappErrorArticle(code)]).toBe(slug);
  });

  it('accepts the code as a string, as a payload may carry it', () => {
    expect(whatsappErrorArticle('131049')).toBe('whatsappError131049');
  });

  it('resolves nothing for a code this installation has no article for', () => {
    expect(whatsappErrorArticle(133010)).toBeUndefined();
  });

  it.each([null, undefined, ''])('resolves nothing for %p', code => {
    expect(whatsappErrorArticle(code)).toBeUndefined();
  });

  it('cannot be tricked into resolving an unrelated registry key', () => {
    expect(whatsappErrorArticle('Window')).toBeUndefined();
  });
});
