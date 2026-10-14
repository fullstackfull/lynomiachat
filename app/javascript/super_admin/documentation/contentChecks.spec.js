import {
  imagesMissingAlt,
  dataImageDestinations,
  mediaKeyOnLine,
} from './contentChecks';

describe('imagesMissingAlt', () => {
  it('finds an image with no alt text at all', () => {
    expect(imagesMissingAlt('![](media:a/b.png)')).toEqual([
      { line: 1, alt: '', destination: 'media:a/b.png' },
    ]);
  });

  it('finds an image whose alt is only whitespace', () => {
    expect(imagesMissingAlt('![   ](media:a/b.png)')).toHaveLength(1);
  });

  it('accepts a real alt', () => {
    expect(imagesMissingAlt('![Step two](media:a/b.png)')).toEqual([]);
  });

  it('reports the line number so the operator can find it', () => {
    const source = 'intro\n\n![ok](media:a/b.png)\n\n![](media:c/d.png)';
    expect(imagesMissingAlt(source).map(i => i.line)).toEqual([5]);
  });

  it('finds every missing alt on one line', () => {
    expect(
      imagesMissingAlt('![](media:a.png) and ![](media:b.png)')
    ).toHaveLength(2);
  });

  // An image inside a fence is sample source an article is explaining, not an image.
  it('ignores an image inside a fenced code block', () => {
    const source =
      'how to write one:\n\n```markdown\n![](media:a/b.png)\n```\n\ndone';
    expect(imagesMissingAlt(source)).toEqual([]);
  });

  it('resumes checking after the fence closes', () => {
    const source = '```\n![](media:inside.png)\n```\n\n![](media:outside.png)';
    expect(imagesMissingAlt(source).map(i => i.destination)).toEqual([
      'media:outside.png',
    ]);
  });

  it('is quiet on an article with no images, which is every corpus file today', () => {
    expect(
      imagesMissingAlt('# Title\n\nSome **prose** and a [link](other-article).')
    ).toEqual([]);
  });
});

describe('dataImageDestinations', () => {
  // R2-MEDIA-INTERFACE.md 8.2: writing a data: image into `content` is out of bounds, so a paste of one is
  // refused rather than stored.
  it('catches a base64 image destination', () => {
    const found = dataImageDestinations(
      '![x](data:image/png;base64,iVBORw0KGgo=)'
    );
    expect(found).toHaveLength(1);
    expect(found[0].line).toBe(1);
  });

  it('catches it whatever the case', () => {
    expect(
      dataImageDestinations('![x](DATA:image/gif;base64,R0lGOD)')
    ).toHaveLength(1);
  });

  it('leaves a media: key alone', () => {
    expect(dataImageDestinations('![x](media:a/b.png)')).toEqual([]);
  });

  it('leaves a data: URL inside a fence alone, where it is documentation', () => {
    expect(
      dataImageDestinations('```\n![x](data:image/png;base64,AA)\n```')
    ).toEqual([]);
  });
});

describe('mediaKeyOnLine', () => {
  const line = '![Step two](media:uploads/8f3a1c2b5d7e9a04-step-two.png)';

  it('reads back the key of the image the caret is on, so Replace can name it', () => {
    expect(mediaKeyOnLine(`intro\n\n${line}\n\nmore`, 10)).toBe(
      'uploads/8f3a1c2b5d7e9a04-step-two.png'
    );
  });

  it('finds it from anywhere on the line, not only the start', () => {
    expect(mediaKeyOnLine(line, line.length - 1)).toBe(
      'uploads/8f3a1c2b5d7e9a04-step-two.png'
    );
  });

  it('is null when the caret is on prose', () => {
    expect(mediaKeyOnLine(`prose\n${line}`, 2)).toBeNull();
  });

  it('ignores an image whose destination is not a media key', () => {
    expect(mediaKeyOnLine('![x](https://example.com/a.png)', 2)).toBeNull();
  });
});
